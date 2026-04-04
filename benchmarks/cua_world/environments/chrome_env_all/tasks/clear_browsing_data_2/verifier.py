#!/usr/bin/env python3
"""
Verifier for Chrome Clear Browsing Data Task (clear_browsing_data@1)
Task: Clear browsing history from the last hour while preserving older history and cookies

Verification Strategy:
1. Compare History database before and after the task
2. Verify recent entries (< 1 hour) were deleted
3. Verify old entries (> 1 day) were preserved
4. Verify Cookies database was not modified
5. Verify database integrity after deletion
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add Chrome verification utilities to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utils not available")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for clear_browsing_data task.
    
    Verification Checklist:
    ✅ Recent History Deleted: Entries within last hour are removed
    ✅ Old History Preserved: Entries older than 1 day remain
    ✅ Cookies Preserved: Cookies database unchanged
    ✅ Database Integrity: History database valid and not corrupted
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = None
    try:
        # Create temporary directory for verification files
        temp_dir = tempfile.mkdtemp(prefix="chrome_clear_data_verify_")
        logger.info(f"Using temp directory: {temp_dir}")
        
        # Copy required files from container
        files_needed = {
            'history_before': '/tmp/history_before.db',
            'history_after': '/tmp/history_after.db',
            'cookies_before': '/tmp/cookies_before.db',
            'cookies_after': '/tmp/cookies_after.db',
            'cutoff_timestamp': '/tmp/history_cutoff_timestamp.txt'
        }
        
        local_files = {}
        for key, container_path in files_needed.items():
            local_path = os.path.join(temp_dir, os.path.basename(container_path))
            try:
                success, error = copy_from_env(container_path, local_path)
                if success and os.path.exists(local_path):
                    local_files[key] = local_path
                    logger.info(f"✓ Copied {key}: {os.path.getsize(local_path)} bytes")
                else:
                    logger.warning(f"⚠ Failed to copy {key}: {error}")
            except Exception as e:
                logger.warning(f"⚠ Error copying {key}: {e}")
        
        # Verify we have minimum required files
        if 'history_before' not in local_files or 'history_after' not in local_files:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Missing required history database files"
            }
        
        # Read cutoff timestamp (1 hour ago in Chrome format)
        cutoff_timestamp = None
        if 'cutoff_timestamp' in local_files:
            try:
                with open(local_files['cutoff_timestamp'], 'r') as f:
                    cutoff_timestamp = int(f.read().strip())
                logger.info(f"Cutoff timestamp: {cutoff_timestamp}")
            except Exception as e:
                logger.warning(f"Could not read cutoff timestamp: {e}")
        
        # Perform verification
        results = {
            'recent_deleted': False,
            'old_preserved': False,
            'cookies_preserved': False,
            'db_integrity': False
        }
        
        feedback_details = []
        
        # 1. Check recent history deletion
        try:
            recent_check = check_recent_history_deleted(
                local_files['history_before'],
                local_files['history_after'],
                cutoff_timestamp
            )
            results['recent_deleted'] = recent_check['success']
            feedback_details.append(recent_check['feedback'])
            logger.info(f"Recent history deleted: {recent_check['success']}")
        except Exception as e:
            feedback_details.append(f"Recent history check failed: {str(e)}")
            logger.error(f"Recent history check error: {e}", exc_info=True)
        
        # 2. Check old history preservation
        try:
            old_check = check_old_history_preserved(
                local_files['history_before'],
                local_files['history_after'],
                cutoff_timestamp
            )
            results['old_preserved'] = old_check['success']
            feedback_details.append(old_check['feedback'])
            logger.info(f"Old history preserved: {old_check['success']}")
        except Exception as e:
            feedback_details.append(f"Old history check failed: {str(e)}")
            logger.error(f"Old history check error: {e}", exc_info=True)
        
        # 3. Check cookies preservation
        if 'cookies_before' in local_files and 'cookies_after' in local_files:
            try:
                cookies_check = check_cookies_unchanged(
                    local_files['cookies_before'],
                    local_files['cookies_after']
                )
                results['cookies_preserved'] = cookies_check['success']
                feedback_details.append(cookies_check['feedback'])
                logger.info(f"Cookies preserved: {cookies_check['success']}")
            except Exception as e:
                feedback_details.append(f"Cookies check failed: {str(e)}")
                logger.error(f"Cookies check error: {e}", exc_info=True)
        else:
            # If cookies databases not available, assume preserved
            results['cookies_preserved'] = True
            feedback_details.append("Cookies preservation: assumed (files not available)")
        
        # 4. Check database integrity
        try:
            integrity_check = check_database_integrity(local_files['history_after'])
            results['db_integrity'] = integrity_check['success']
            feedback_details.append(integrity_check['feedback'])
            logger.info(f"Database integrity: {integrity_check['success']}")
        except Exception as e:
            feedback_details.append(f"Integrity check failed: {str(e)}")
            logger.error(f"Integrity check error: {e}", exc_info=True)
        
        # Calculate score based on criteria
        criteria_met = sum(results.values())
        total_criteria = len(results)
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3 out of 4 criteria
        
        feedback = f"Verification complete: {criteria_met}/{total_criteria} criteria met\n" + \
                   "\n".join(feedback_details)
        
        logger.info(f"Final result: {criteria_met}/{total_criteria} criteria, score={score}, passed={passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": results
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temporary files
        if temp_dir and os.path.exists(temp_dir):
            import shutil
            try:
                shutil.rmtree(temp_dir)
                logger.info(f"Cleaned up temp directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")


def check_recent_history_deleted(history_before_path: str, history_after_path: str, 
                                 cutoff_timestamp: Optional[int]) -> Dict:
    """
    Verify that recent history entries (< 1 hour) were deleted.
    
    Returns:
        Dict with 'success' (bool) and 'feedback' (str)
    """
    try:
        # Parse history entries
        before_recent = get_history_entries_by_time(history_before_path, cutoff_timestamp, recent=True)
        after_recent = get_history_entries_by_time(history_after_path, cutoff_timestamp, recent=True)
        
        before_count = len(before_recent)
        after_count = len(after_recent)
        deleted_count = before_count - after_count
        
        logger.info(f"Recent entries: {before_count} before → {after_count} after ({deleted_count} deleted)")
        
        # Success if at least 2 recent entries were deleted and fewer remain
        if before_count >= 2 and after_count < before_count:
            deletion_rate = deleted_count / before_count if before_count > 0 else 0
            if deletion_rate >= 0.5:  # At least 50% of recent entries deleted
                return {
                    'success': True,
                    'feedback': f"✓ Recent history deleted: {deleted_count}/{before_count} entries removed"
                }
        
        return {
            'success': False,
            'feedback': f"✗ Recent history not properly deleted: {before_count} before → {after_count} after"
        }
        
    except Exception as e:
        logger.error(f"Recent history check error: {e}")
        return {'success': False, 'feedback': f"Recent history check error: {str(e)}"}


def check_old_history_preserved(history_before_path: str, history_after_path: str,
                                cutoff_timestamp: Optional[int]) -> Dict:
    """
    Verify that old history entries (> 1 day) were preserved.
    
    Returns:
        Dict with 'success' (bool) and 'feedback' (str)
    """
    try:
        # Parse history entries
        before_old = get_history_entries_by_time(history_before_path, cutoff_timestamp, recent=False)
        after_old = get_history_entries_by_time(history_after_path, cutoff_timestamp, recent=False)
        
        before_count = len(before_old)
        after_count = len(after_old)
        
        logger.info(f"Old entries: {before_count} before → {after_count} after")
        
        # Success if old entries remain (at least 80% preserved)
        if before_count > 0:
            preservation_rate = after_count / before_count
            if preservation_rate >= 0.8:
                return {
                    'success': True,
                    'feedback': f"✓ Old history preserved: {after_count}/{before_count} entries remain"
                }
        
        return {
            'success': False,
            'feedback': f"✗ Old history not preserved: {before_count} before → {after_count} after"
        }
        
    except Exception as e:
        logger.error(f"Old history check error: {e}")
        return {'success': False, 'feedback': f"Old history check error: {str(e)}"}


def check_cookies_unchanged(cookies_before_path: str, cookies_after_path: str) -> Dict:
    """
    Verify that cookies database was not modified.
    
    Returns:
        Dict with 'success' (bool) and 'feedback' (str)
    """
    try:
        # Count cookies before and after
        before_count = count_cookies(cookies_before_path)
        after_count = count_cookies(cookies_after_path)
        
        logger.info(f"Cookies: {before_count} before → {after_count} after")
        
        # Allow small variation (±2 cookies) due to session cookies
        if abs(after_count - before_count) <= 2:
            return {
                'success': True,
                'feedback': f"✓ Cookies preserved: {before_count} → {after_count} (no significant change)"
            }
        
        return {
            'success': False,
            'feedback': f"✗ Cookies modified: {before_count} → {after_count}"
        }
        
    except Exception as e:
        logger.error(f"Cookies check error: {e}")
        return {'success': False, 'feedback': f"Cookies check error: {str(e)}"}


def check_database_integrity(history_path: str) -> Dict:
    """
    Verify that the History database is valid and not corrupted.
    
    Returns:
        Dict with 'success' (bool) and 'feedback' (str)
    """
    try:
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        
        # Check if we can query the database
        cursor.execute("SELECT COUNT(*) FROM urls")
        url_count = cursor.fetchone()[0]
        
        cursor.execute("SELECT COUNT(*) FROM visits")
        visit_count = cursor.fetchone()[0]
        
        # Run SQLite integrity check
        cursor.execute("PRAGMA integrity_check")
        integrity_result = cursor.fetchone()[0]
        
        conn.close()
        
        if integrity_result.lower() == 'ok':
            return {
                'success': True,
                'feedback': f"✓ Database integrity OK ({url_count} urls, {visit_count} visits)"
            }
        else:
            return {
                'success': False,
                'feedback': f"✗ Database integrity check failed: {integrity_result}"
            }
        
    except Exception as e:
        logger.error(f"Database integrity check error: {e}")
        return {'success': False, 'feedback': f"Database integrity error: {str(e)}"}


def get_history_entries_by_time(history_path: str, cutoff_timestamp: Optional[int],
                                recent: bool = True) -> List[Dict]:
    """
    Get history entries filtered by time.
    
    Args:
        history_path: Path to History database
        cutoff_timestamp: Chrome timestamp for cutoff (entries newer than this are "recent")
        recent: If True, return recent entries; if False, return old entries
    
    Returns:
        List of history entry dicts
    """
    try:
        conn = sqlite3.connect(history_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Get test entries (ids >= 100001)
        cursor.execute("""
            SELECT id, url, title, last_visit_time, visit_count
            FROM urls
            WHERE id >= 100001
            ORDER BY last_visit_time DESC
        """)
        
        entries = []
        for row in cursor.fetchall():
            entry = dict(row)
            
            # Filter by timestamp if available
            if cutoff_timestamp is not None:
                is_recent = entry['last_visit_time'] > cutoff_timestamp
                if (recent and is_recent) or (not recent and not is_recent):
                    entries.append(entry)
            else:
                # Fallback: use simple heuristic based on entry ID
                # IDs 100004-100006 are recent, 100001-100003 are old
                is_recent_by_id = entry['id'] >= 100004
                if (recent and is_recent_by_id) or (not recent and not is_recent_by_id):
                    entries.append(entry)
        
        conn.close()
        return entries
        
    except Exception as e:
        logger.error(f"Error reading history entries: {e}")
        return []


def count_cookies(cookies_path: str) -> int:
    """
    Count total cookies in the Cookies database.
    
    Args:
        cookies_path: Path to Cookies database
    
    Returns:
        Number of cookies
    """
    try:
        conn = sqlite3.connect(cookies_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM cookies")
        count = cursor.fetchone()[0]
        conn.close()
        return count
    except Exception as e:
        logger.error(f"Error counting cookies: {e}")
        return 0
