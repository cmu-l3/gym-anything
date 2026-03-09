#!/usr/bin/env python3
"""
Verifier for Chrome Selective History Deletion Task (history_selective_clear@1)
Task: Search history for entries containing 'example' keyword and selectively delete them

Verification Strategy:
- Copy final History SQLite database from container
- Query for entries containing target keyword (should be 0)
- Verify preservation of non-target entries (should be ≥3)
- Compare with baseline if available to check deletion scope
- Validate database integrity
"""

import logging
import sys
import os
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        parse_history,
        check_history_contains_keyword,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for history_selective_clear@1.
    
    Verifies:
    1. Target keyword entries are deleted (0 matches)
    2. Non-target entries are preserved (≥3 entries remain)
    3. Deletion scope is reasonable (1-10 entries deleted, not entire history)
    4. Database integrity is maintained
    
    Scoring:
    - 100%: All 4 criteria met
    - 75-99%: 3/4 criteria met  
    - 50-74%: 2/4 criteria met
    - 0-49%: <2 criteria met
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration including target_keyword
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    # Get target keyword from task config (default: "example")
    target_keyword = task_info.get('target_keyword', 'example')
    logger.info(f"Target keyword for deletion: '{target_keyword}'")

    try:
        # Get history databases
        final_history, baseline_history, error_msg = get_history_databases(copy_from_env)
        
        if final_history is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve history database: {error_msg}"
            }
        
        # Perform verification
        result = verify_selective_deletion(
            final_history,
            baseline_history,
            target_keyword
        )
        
        # Cleanup temporary files
        cleanup_temp_history_files(final_history, baseline_history)
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_history_databases(copy_from_env) -> Tuple[str, str, str]:
    """
    Retrieve final and baseline history databases from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (final_history_path, baseline_history_path, error_message)
        Paths will be None if files couldn't be retrieved
    """
    final_history = None
    baseline_history = None
    
    # Try to get final history database
    try:
        temp_final = tempfile.NamedTemporaryFile(delete=False, suffix='_final.db')
        temp_final.close()
        
        # Try multiple possible locations for final history
        final_paths = [
            "/tmp/history_final.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        for container_path in final_paths:
            try:
                logger.info(f"Trying to copy final history from: {container_path}")
                copy_from_env(container_path, temp_final.name)
                
                # Check if file has content and is valid SQLite
                if Path(temp_final.name).stat().st_size > 0:
                    if is_valid_sqlite(temp_final.name):
                        final_history = temp_final.name
                        logger.info(f"✓ Successfully copied final history from: {container_path}")
                        break
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        if final_history is None:
            os.unlink(temp_final.name)
            return None, None, "Could not retrieve final history database from any location"
            
    except Exception as e:
        return None, None, f"Error retrieving final history: {str(e)}"
    
    # Try to get baseline history (optional, used for scope verification)
    try:
        temp_baseline = tempfile.NamedTemporaryFile(delete=False, suffix='_baseline.db')
        temp_baseline.close()
        
        copy_from_env("/tmp/history_baseline.db", temp_baseline.name)
        
        if Path(temp_baseline.name).stat().st_size > 0 and is_valid_sqlite(temp_baseline.name):
            baseline_history = temp_baseline.name
            logger.info("✓ Successfully retrieved baseline history for comparison")
        else:
            os.unlink(temp_baseline.name)
            logger.info("⚠ Baseline history not available (scope check will be skipped)")
    except Exception as e:
        logger.info(f"Baseline history not available: {e}")
    
    return final_history, baseline_history, ""


def is_valid_sqlite(db_path: str) -> bool:
    """Check if file is a valid SQLite database."""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='urls';")
        result = cursor.fetchone()
        conn.close()
        return result is not None
    except Exception as e:
        logger.warning(f"SQLite validation failed: {e}")
        return False


def query_history_keyword(db_path: str, keyword: str) -> Tuple[int, List[Tuple[str, str]]]:
    """
    Query history database for entries containing keyword.
    
    Args:
        db_path: Path to History SQLite database
        keyword: Keyword to search for in URLs and titles
        
    Returns:
        Tuple of (count, list of (url, title) tuples)
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        query = """
            SELECT url, title FROM urls 
            WHERE url LIKE ? OR title LIKE ?
            ORDER BY last_visit_time DESC
        """
        
        cursor.execute(query, (f'%{keyword}%', f'%{keyword}%'))
        results = cursor.fetchall()
        conn.close()
        
        return len(results), results
        
    except Exception as e:
        logger.error(f"Error querying history: {e}")
        return -1, []


def count_total_history_entries(db_path: str) -> int:
    """Count total number of entries in history database."""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM urls")
        count = cursor.fetchone()[0]
        conn.close()
        return count
    except Exception as e:
        logger.error(f"Error counting history entries: {e}")
        return -1


def verify_selective_deletion(final_history: str, baseline_history: str, keyword: str) -> Dict[str, Any]:
    """
    Verify that selective deletion was performed correctly.
    
    Args:
        final_history: Path to final history database
        baseline_history: Path to baseline history database (may be None)
        keyword: Target keyword that should be deleted
        
    Returns:
        Verification result dict with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Target keyword should be absent (deleted)
    logger.info("Criterion 1: Checking if target keyword entries are deleted...")
    keyword_count, keyword_entries = query_history_keyword(final_history, keyword)
    
    if keyword_count == -1:
        feedback_parts.append(f"✗ Database query error")
        keyword_deleted = False
    elif keyword_count == 0:
        feedback_parts.append(f"✓ Target keyword '{keyword}' successfully deleted (0 matches)")
        criteria_met += 1
        keyword_deleted = True
    else:
        feedback_parts.append(f"✗ Target keyword '{keyword}' still present ({keyword_count} entries remain)")
        keyword_deleted = False
        # Log some examples
        for url, title in keyword_entries[:3]:
            logger.info(f"   Remaining entry: {url}")
    
    # Criterion 2: Other entries should be preserved (at least 3)
    logger.info("Criterion 2: Checking if non-target entries are preserved...")
    total_count = count_total_history_entries(final_history)
    
    min_preserved = 3
    if total_count == -1:
        feedback_parts.append(f"✗ Could not count preserved entries")
        preservation_ok = False
    elif total_count >= min_preserved:
        feedback_parts.append(f"✓ History preserved ({total_count} entries remain, need ≥{min_preserved})")
        criteria_met += 1
        preservation_ok = True
    else:
        feedback_parts.append(f"✗ Too few entries preserved ({total_count} < {min_preserved})")
        preservation_ok = False
    
    # Criterion 3: Reasonable deletion scope (if baseline available)
    logger.info("Criterion 3: Checking deletion scope...")
    scope_ok = True  # Default to True if baseline not available
    
    if baseline_history and os.path.exists(baseline_history):
        baseline_count = count_total_history_entries(baseline_history)
        baseline_keyword_count, _ = query_history_keyword(baseline_history, keyword)
        
        if baseline_count > 0 and total_count >= 0:
            deleted_count = baseline_count - total_count
            
            # Check scope: should delete 1-10 entries, not entire history
            if deleted_count < 1:
                feedback_parts.append(f"✗ No entries were deleted (baseline: {baseline_count}, final: {total_count})")
                scope_ok = False
            elif deleted_count > 10:
                feedback_parts.append(f"✗ Too many entries deleted ({deleted_count} entries, expected 1-10)")
                scope_ok = False
            elif total_count == 0:
                feedback_parts.append(f"✗ Entire history was deleted (should preserve non-target entries)")
                scope_ok = False
            else:
                feedback_parts.append(f"✓ Reasonable deletion scope ({deleted_count} entries deleted)")
                criteria_met += 1
        else:
            feedback_parts.append(f"⚠ Could not verify deletion scope (baseline data incomplete)")
    else:
        feedback_parts.append(f"⚠ Baseline not available, deletion scope check skipped")
        # Still award point if other criteria suggest reasonable behavior
        if keyword_deleted and preservation_ok and total_count > 0:
            criteria_met += 1
    
    # Criterion 4: Database integrity
    logger.info("Criterion 4: Checking database integrity...")
    integrity_ok = is_valid_sqlite(final_history) and total_count >= 0
    
    if integrity_ok:
        feedback_parts.append(f"✓ Database integrity maintained")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Database integrity compromised or corrupted")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "keyword_deleted": keyword_deleted,
            "keyword_count": keyword_count,
            "preserved_count": total_count,
            "criteria_met": criteria_met,
            "scope_ok": scope_ok,
            "integrity_ok": integrity_ok
        }
    }


def cleanup_temp_history_files(*file_paths):
    """Clean up temporary history database files."""
    for path in file_paths:
        if path and os.path.exists(path):
            try:
                os.unlink(path)
                logger.debug(f"Cleaned up temp file: {path}")
            except Exception as e:
                logger.warning(f"Could not clean up {path}: {e}")
