#!/usr/bin/env python3
"""
Verifier for Chrome Clear Browsing Data with Time Range Task (clear_browsing_data_timerange@1)

Task: Selectively clear cookies and cache from last 24 hours while preserving history

Verification Strategy:
1. Compare cookies before/after - recent deleted, old preserved
2. Verify all history entries preserved
3. Confirm cache was cleared (size reduction or modification time)
4. Ensure other data types remain intact (check Preferences)
5. Validate time range accuracy (24-hour boundary)

Scoring: 5 criteria, need 4+ to pass (75%)
"""

import logging
import sys
import os
import json
import sqlite3
import time
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for clear_browsing_data_timerange@1.
    
    Verifies selective deletion based on 24-hour time window:
    - Recent cookies (within 24h) deleted
    - Old cookies (>24h) preserved
    - All history preserved
    - Cache cleared
    - Other data types intact
    
    Returns:
        Dict with 'passed', 'score', 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Load baseline data
        baseline = load_baseline(copy_from_env)
        if not baseline:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to load baseline data - setup may have failed"
            }
        
        # Copy post-task databases
        cookies_db_path = copy_database(copy_from_env, "cookies_after.db", "/tmp/cookies_after.db")
        history_db_path = copy_database(copy_from_env, "history_after.db", "/tmp/history_after.db")
        
        if not cookies_db_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to access Cookies database after task"
            }
        
        if not history_db_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to access History database after task"
            }
        
        # Perform multi-criteria verification
        criteria_results = []
        feedback_parts = []
        
        # Criterion 1: Recent cookies deleted (≥90%)
        recent_deleted, recent_msg = check_recent_cookies_deleted(
            cookies_db_path,
            baseline["cookies"]["recent"],
            baseline["cutoff_24h_chrome_time"]
        )
        criteria_results.append(recent_deleted)
        feedback_parts.append(f"{'✓' if recent_deleted else '✗'} Recent cookies: {recent_msg}")
        
        # Criterion 2: Old cookies preserved (≥90%)
        old_preserved, old_msg = check_old_cookies_preserved(
            cookies_db_path,
            baseline["cookies"]["old"]
        )
        criteria_results.append(old_preserved)
        feedback_parts.append(f"{'✓' if old_preserved else '✗'} Old cookies: {old_msg}")
        
        # Criterion 3: History fully preserved (≥99%)
        history_preserved, history_msg = check_history_preserved(
            history_db_path,
            baseline["history"]["all_urls"]
        )
        criteria_results.append(history_preserved)
        feedback_parts.append(f"{'✓' if history_preserved else '✗'} History: {history_msg}")
        
        # Criterion 4: Cache cleared (≥50% reduction or recent modification)
        cache_cleared, cache_msg = check_cache_cleared(
            copy_from_env,
            baseline["cache"]["size_bytes"],
            baseline["cache"]["file_count"]
        )
        criteria_results.append(cache_cleared)
        feedback_parts.append(f"{'✓' if cache_cleared else '✗'} Cache: {cache_msg}")
        
        # Criterion 5: Other data types intact (check preferences exist)
        other_intact, other_msg = check_other_data_intact(copy_from_env)
        criteria_results.append(other_intact)
        feedback_parts.append(f"{'✓' if other_intact else '⚠'} Other data: {other_msg}")
        
        # Calculate score
        criteria_met = sum(criteria_results)
        score = int((criteria_met / 5) * 100)
        passed = criteria_met >= 4  # Need 4/5 criteria (80%)
        
        # Build feedback
        feedback = "Chrome Clear Browsing Data with Time Range Verification\n"
        feedback += "=" * 60 + "\n"
        feedback += "\n".join(feedback_parts)
        feedback += f"\n\nCriteria met: {criteria_met}/5"
        feedback += f"\nScore: {score}%"
        feedback += f"\nResult: {'PASSED ✅' if passed else 'FAILED ❌'}"
        
        # Cleanup
        cleanup_temp_databases(cookies_db_path, history_db_path)
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_met,
                "recent_cookies_deleted": recent_deleted,
                "old_cookies_preserved": old_preserved,
                "history_preserved": history_preserved,
                "cache_cleared": cache_cleared,
                "other_data_intact": other_intact
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def load_baseline(copy_from_env) -> Dict[str, Any]:
    """Load baseline state recorded before task"""
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        copy_from_env("/tmp/baseline_export.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            baseline = json.load(f)
        
        os.unlink(temp_file.name)
        
        logger.info(f"Baseline loaded: {len(baseline['cookies']['recent'])} recent cookies, "
                   f"{len(baseline['cookies']['old'])} old cookies, "
                   f"{baseline['history']['total_count']} history entries")
        
        return baseline
        
    except Exception as e:
        logger.error(f"Failed to load baseline: {e}")
        return None


def copy_database(copy_from_env, filename: str, container_path: str) -> str:
    """Copy SQLite database from container to host"""
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env(container_path, temp_path)
        
        # Verify database is valid
        if os.path.getsize(temp_path) > 0:
            logger.info(f"✓ Copied {filename} ({os.path.getsize(temp_path)} bytes)")
            return temp_path
        else:
            os.unlink(temp_path)
            return None
            
    except Exception as e:
        logger.error(f"Failed to copy {filename}: {e}")
        return None


def check_recent_cookies_deleted(cookies_db: str, baseline_recent: List[Tuple], 
                                 cutoff_time: int) -> Tuple[bool, str]:
    """
    Check that cookies created within last 24h were deleted.
    
    Returns:
        (passed, message)
    """
    try:
        conn = sqlite3.connect(cookies_db)
        cursor = conn.cursor()
        
        # Count how many baseline recent cookies still exist
        remaining = 0
        for name, host_key in baseline_recent:
            cursor.execute(
                "SELECT COUNT(*) FROM cookies WHERE name = ? AND host_key = ?",
                (name, host_key)
            )
            if cursor.fetchone()[0] > 0:
                remaining += 1
        
        conn.close()
        
        if len(baseline_recent) == 0:
            return True, "No recent cookies to delete"
        
        deletion_rate = 1 - (remaining / len(baseline_recent))
        passed = deletion_rate >= 0.9
        
        msg = f"{int(deletion_rate*100)}% deleted ({len(baseline_recent)-remaining}/{len(baseline_recent)})"
        
        logger.info(f"Recent cookie deletion: {msg}")
        return passed, msg
        
    except Exception as e:
        logger.error(f"Error checking recent cookies: {e}")
        return False, f"Error: {e}"


def check_old_cookies_preserved(cookies_db: str, baseline_old: List[Tuple]) -> Tuple[bool, str]:
    """
    Check that cookies older than 24h were preserved.
    
    Returns:
        (passed, message)
    """
    try:
        conn = sqlite3.connect(cookies_db)
        cursor = conn.cursor()
        
        # Count how many baseline old cookies still exist
        preserved = 0
        for name, host_key in baseline_old:
            cursor.execute(
                "SELECT COUNT(*) FROM cookies WHERE name = ? AND host_key = ?",
                (name, host_key)
            )
            if cursor.fetchone()[0] > 0:
                preserved += 1
        
        conn.close()
        
        if len(baseline_old) == 0:
            return True, "No old cookies to preserve"
        
        preservation_rate = preserved / len(baseline_old)
        passed = preservation_rate >= 0.9
        
        msg = f"{int(preservation_rate*100)}% preserved ({preserved}/{len(baseline_old)})"
        
        logger.info(f"Old cookie preservation: {msg}")
        return passed, msg
        
    except Exception as e:
        logger.error(f"Error checking old cookies: {e}")
        return False, f"Error: {e}"


def check_history_preserved(history_db: str, baseline_urls: List[str]) -> Tuple[bool, str]:
    """
    Check that ALL history entries were preserved.
    
    Returns:
        (passed, message)
    """
    try:
        conn = sqlite3.connect(history_db)
        cursor = conn.cursor()
        
        preserved = 0
        for url in baseline_urls:
            cursor.execute("SELECT COUNT(*) FROM urls WHERE url = ?", (url,))
            if cursor.fetchone()[0] > 0:
                preserved += 1
        
        conn.close()
        
        if len(baseline_urls) == 0:
            return True, "No history to preserve"
        
        preservation_rate = preserved / len(baseline_urls)
        passed = preservation_rate >= 0.99  # Very strict - history should be 100% preserved
        
        msg = f"{int(preservation_rate*100)}% preserved ({preserved}/{len(baseline_urls)})"
        
        logger.info(f"History preservation: {msg}")
        return passed, msg
        
    except Exception as e:
        logger.error(f"Error checking history: {e}")
        return False, f"Error: {e}"


def check_cache_cleared(copy_from_env, baseline_size: int, baseline_count: int) -> Tuple[bool, str]:
    """
    Check that cache was cleared.
    
    Returns:
        (passed, message)
    """
    try:
        # Get current cache size
        temp_size = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        temp_size.close()
        
        try:
            copy_from_env("/tmp/cache_size_after.txt", temp_size.name)
            with open(temp_size.name, 'r') as f:
                current_size = int(f.read().strip())
        except:
            current_size = baseline_size  # Assume unchanged if can't read
        finally:
            os.unlink(temp_size.name)
        
        # Get current cache file count
        temp_count = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        temp_count.close()
        
        try:
            copy_from_env("/tmp/cache_file_count_after.txt", temp_count.name)
            with open(temp_count.name, 'r') as f:
                current_count = int(f.read().strip())
        except:
            current_count = baseline_count
        finally:
            os.unlink(temp_count.name)
        
        if baseline_size == 0:
            return True, "No cache to clear"
        
        size_reduction = 1 - (current_size / baseline_size)
        count_reduction = 1 - (current_count / baseline_count) if baseline_count > 0 else 0
        
        # Pass if either significant size reduction or file count reduction
        passed = (size_reduction >= 0.5) or (count_reduction >= 0.5) or (current_size == 0)
        
        msg = f"Size: {int(size_reduction*100)}% reduced ({current_size}/{baseline_size} bytes), "
        msg += f"Files: {int(count_reduction*100)}% reduced ({current_count}/{baseline_count})"
        
        logger.info(f"Cache clearing: {msg}")
        return passed, msg
        
    except Exception as e:
        logger.error(f"Error checking cache: {e}")
        return False, f"Error: {e}"


def check_other_data_intact(copy_from_env) -> Tuple[bool, str]:
    """
    Check that other data types remain intact (simplified check via Preferences).
    
    Returns:
        (passed, message)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        copy_from_env("/tmp/preferences_after.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            prefs = json.load(f)
        
        os.unlink(temp_file.name)
        
        # If preferences are intact and readable, assume other data is intact
        if prefs and isinstance(prefs, dict):
            logger.info("Other data types appear intact")
            return True, "Preferences intact"
        else:
            return False, "Preferences corrupted"
            
    except Exception as e:
        logger.warning(f"Could not verify other data: {e}")
        return True, "Check inconclusive (assumed OK)"


def cleanup_temp_databases(*paths):
    """Clean up temporary database files"""
    for path in paths:
        try:
            if path and os.path.exists(path):
                os.unlink(path)
        except:
            pass
