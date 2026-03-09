#!/usr/bin/env python3
"""
Verifier for Chrome Clear Recent History Task (clear_recent_history@1)
Task: Use Chrome's Clear Browsing Data to selectively delete history from last 24 hours

Verification Strategy:
1. Compare before/after History database snapshots
2. Analyze entries by timestamp (Chrome WebKit format)
3. Verify ≥80% of entries from last 24 hours are deleted
4. Verify ≥90% of entries outside 24 hours are preserved
5. Check for data corruption and selective deletion
"""

import logging
import sys
import os
import sqlite3
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Tuple, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def chrome_timestamp_to_datetime(chrome_timestamp):
    """
    Convert Chrome timestamp to Python datetime.
    Chrome uses WebKit timestamp: microseconds since 1601-01-01 00:00:00 UTC
    """
    if chrome_timestamp == 0:
        return None
    
    # Chrome epoch start
    epoch_start = datetime(1601, 1, 1)
    # Convert microseconds to timedelta
    delta = timedelta(microseconds=chrome_timestamp)
    return epoch_start + delta


def datetime_to_chrome_timestamp(dt):
    """Convert Python datetime to Chrome timestamp"""
    epoch_start = datetime(1601, 1, 1)
    delta = dt - epoch_start
    return int(delta.total_seconds() * 1000000)


def get_history_entries(db_path, cutoff_hours=24):
    """
    Get history entries from database, separated by time range.
    
    Args:
        db_path: Path to History database
        cutoff_hours: Hours to define "recent" (default 24)
        
    Returns:
        Tuple of (recent_entries, older_entries)
        Each entry is dict with id, url, title, timestamp
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Get all entries
        cursor.execute("""
            SELECT id, url, title, visit_count, last_visit_time
            FROM urls
            ORDER BY last_visit_time DESC
        """)
        
        all_entries = cursor.fetchall()
        conn.close()
        
        # Calculate cutoff time
        now = datetime.now()
        cutoff_time = now - timedelta(hours=cutoff_hours)
        cutoff_chrome_ts = datetime_to_chrome_timestamp(cutoff_time)
        
        recent_entries = []
        older_entries = []
        
        for entry_id, url, title, visit_count, last_visit_time in all_entries:
            entry_dict = {
                'id': entry_id,
                'url': url,
                'title': title,
                'visit_count': visit_count,
                'timestamp': last_visit_time,
                'datetime': chrome_timestamp_to_datetime(last_visit_time)
            }
            
            if last_visit_time >= cutoff_chrome_ts:
                recent_entries.append(entry_dict)
            else:
                older_entries.append(entry_dict)
        
        logger.info(f"Loaded {len(recent_entries)} recent entries, {len(older_entries)} older entries from {db_path}")
        
        return recent_entries, older_entries
        
    except Exception as e:
        logger.error(f"Error reading history database {db_path}: {e}")
        return [], []


def verify_selective_deletion(before_db_path, after_db_path, cutoff_hours=24):
    """
    Verify that recent history was selectively deleted while older history preserved.
    
    Args:
        before_db_path: Path to History database before task
        after_db_path: Path to History database after task
        cutoff_hours: Hours defining "recent" (default 24)
        
    Returns:
        Dict with verification results
    """
    # Get entries from both databases
    recent_before, older_before = get_history_entries(before_db_path, cutoff_hours)
    recent_after, older_after = get_history_entries(after_db_path, cutoff_hours)
    
    logger.info("=" * 60)
    logger.info("VERIFICATION ANALYSIS")
    logger.info("=" * 60)
    logger.info(f"Before: {len(recent_before)} recent, {len(older_before)} older")
    logger.info(f"After:  {len(recent_after)} recent, {len(older_after)} older")
    
    # Criterion 1: Recent history cleared (≥80% deleted)
    if len(recent_before) == 0:
        recent_deletion_rate = 0.0
        recent_cleared = False
        recent_feedback = "No recent entries to delete"
    else:
        recent_deleted_count = len(recent_before) - len(recent_after)
        recent_deletion_rate = recent_deleted_count / len(recent_before)
        recent_cleared = recent_deletion_rate >= 0.80
        recent_feedback = f"{recent_deleted_count}/{len(recent_before)} recent entries deleted ({recent_deletion_rate*100:.1f}%)"
    
    logger.info(f"✓ Recent deletion: {recent_feedback} - {'PASS' if recent_cleared else 'FAIL'}")
    
    # Criterion 2: Older history preserved (≥90% preserved)
    if len(older_before) == 0:
        older_preservation_rate = 1.0
        older_preserved = True
        older_feedback = "No older entries to preserve"
    else:
        older_preserved_count = len(older_after)
        older_preservation_rate = older_preserved_count / len(older_before)
        older_preserved = older_preservation_rate >= 0.90
        older_feedback = f"{older_preserved_count}/{len(older_before)} older entries preserved ({older_preservation_rate*100:.1f}%)"
    
    logger.info(f"✓ Older preservation: {older_feedback} - {'PASS' if older_preserved else 'FAIL'}")
    
    # Criterion 3: Selective deletion (clear distinction between deleted and preserved)
    selective_deletion = recent_cleared and older_preserved
    
    # Criterion 4: No data corruption (check that entries exist and are valid)
    try:
        conn_after = sqlite3.connect(after_db_path)
        cursor = conn_after.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url IS NULL OR url = ''")
        null_urls = cursor.fetchone()[0]
        conn_after.close()
        
        no_corruption = (null_urls == 0)
        corruption_feedback = f"No corrupted entries" if no_corruption else f"{null_urls} corrupted entries found"
    except Exception as e:
        no_corruption = False
        corruption_feedback = f"Could not check corruption: {e}"
    
    logger.info(f"✓ Data integrity: {corruption_feedback} - {'PASS' if no_corruption else 'FAIL'}")
    
    # Calculate score
    criteria = [
        recent_cleared,
        older_preserved,
        selective_deletion,
        no_corruption
    ]
    
    criteria_met = sum(criteria)
    score = (criteria_met / 4.0) * 100
    passed = score >= 75
    
    # Build detailed feedback
    feedback_parts = [
        "=" * 60,
        "CLEAR RECENT HISTORY VERIFICATION",
        "=" * 60,
        "",
        f"Time Range: Last {cutoff_hours} hours",
        "",
        "RESULTS:",
        f"  {'✓' if recent_cleared else '✗'} Recent History Cleared: {recent_feedback}",
        f"  {'✓' if older_preserved else '✗'} Older History Preserved: {older_feedback}",
        f"  {'✓' if selective_deletion else '✗'} Selective Deletion: {'Successful' if selective_deletion else 'Failed'}",
        f"  {'✓' if no_corruption else '✗'} Data Integrity: {corruption_feedback}",
        "",
        f"Criteria Met: {criteria_met}/4",
        f"Score: {int(score)}%",
        f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}",
        "=" * 60
    ]
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            "recent_before": len(recent_before),
            "recent_after": len(recent_after),
            "recent_deleted": len(recent_before) - len(recent_after),
            "recent_deletion_rate": recent_deletion_rate,
            "older_before": len(older_before),
            "older_after": len(older_after),
            "older_preserved": len(older_after),
            "older_preservation_rate": older_preservation_rate,
            "criteria_met": criteria_met,
            "criteria": {
                "recent_cleared": recent_cleared,
                "older_preserved": older_preserved,
                "selective_deletion": selective_deletion,
                "no_corruption": no_corruption
            }
        }
    }


def verify_task(traj, env_info, task_info):
    """
    Main verification function for clear_recent_history@1.
    
    Verifies selective history deletion by comparing before/after database snapshots.
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }
    
    try:
        # Create temporary directory for verification
        temp_dir = tempfile.mkdtemp(prefix='chrome_history_verify_')
        logger.info(f"Created temporary verification directory: {temp_dir}")
        
        before_db_path = os.path.join(temp_dir, 'History_before.db')
        after_db_path = os.path.join(temp_dir, 'History_after.db')
        
        # Try to copy before database
        logger.info("Copying before-task History database...")
        before_paths = [
            "/tmp/history_verification/History_before.db",
            "/tmp/History_before.db"
        ]
        
        before_copied = False
        for path in before_paths:
            try:
                copy_from_env(path, before_db_path)
                if os.path.exists(before_db_path) and os.path.getsize(before_db_path) > 0:
                    logger.info(f"✓ Copied before database from: {path}")
                    before_copied = True
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {path}: {e}")
        
        if not before_copied:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access before-task History database snapshot"
            }
        
        # Try to copy after database
        logger.info("Copying after-task History database...")
        after_paths = [
            "/tmp/history_verification/History_after.db",
            "/tmp/History_after.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        after_copied = False
        for path in after_paths:
            try:
                copy_from_env(path, after_db_path)
                if os.path.exists(after_db_path) and os.path.getsize(after_db_path) > 0:
                    logger.info(f"✓ Copied after database from: {path}")
                    after_copied = True
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {path}: {e}")
        
        if not after_copied:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access after-task History database"
            }
        
        # Perform verification
        result = verify_selective_deletion(before_db_path, after_db_path, cutoff_hours=24)
        
        # Clean up temporary files
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
