#!/usr/bin/env python3
"""
Verifier for Chrome History Search and Selective Deletion Task (history_search_delete@1)
Task: Search for shopping-related history entries and delete them while preserving news and work URLs

Verification Strategy:
- Copy Chrome History database (SQLite) from container
- Query for shopping URLs (should be deleted - count = 0)
- Query for news URLs (should be preserved - count >= 2)
- Query for work URLs (should be preserved - count >= 2)
- Verify deletion count is exactly 2 (not more, not less)
- Check database integrity after deletion
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for history_search_delete@1.
    
    Verifies that:
    1. Shopping URLs were deleted (count = 0)
    2. News URLs were preserved (count >= 2)
    3. Work URLs were preserved (count >= 2)
    4. Exactly 2 entries were deleted (not bulk clear)
    5. Database integrity is maintained
    
    Scoring:
    - 100%: All 5 criteria met (perfect selective deletion)
    - 80-99%: 4/5 criteria met (good with minor issues)
    - 60-79%: 3/5 criteria met (adequate but failing)
    - <60%: <3 criteria met (task failed)
    
    Pass threshold: 80% (4 out of 5 criteria)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get initial and final history states
        initial_state = get_initial_state(copy_from_env)
        history_path = get_history_database(copy_from_env)
        
        if not history_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not access Chrome History database"
            }
        
        # Perform verification
        result = verify_selective_deletion(history_path, initial_state)
        
        # Clean up
        cleanup_temp_files(history_path)
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


def get_initial_state(copy_from_env) -> Optional[Dict[str, int]]:
    """
    Get initial history state recorded during setup.
    
    Returns:
        Dict with counts or None if not available
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        copy_from_env("/tmp/initial_history_state.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            state = json.load(f)
        
        os.unlink(temp_file.name)
        logger.info(f"Initial state: {state}")
        return state
        
    except Exception as e:
        logger.warning(f"Could not get initial state: {e}")
        return None


def get_history_database(copy_from_env) -> Optional[str]:
    """
    Copy History database from container to local temp file.
    
    Returns:
        Path to local History database file or None if failed
    """
    # Try multiple possible locations
    possible_paths = [
        "/tmp/history_export.db",
        "/home/ga/.config/google-chrome-cdp/Default/History",
        "/home/ga/.config/google-chrome/Default/History"
    ]
    
    for container_path in possible_paths:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
            temp_path = temp_file.name
            temp_file.close()
            
            logger.info(f"Trying to copy History from: {container_path}")
            copy_from_env(container_path, temp_path)
            
            # Verify file was copied and has content
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                # Verify it's a valid SQLite database
                try:
                    conn = sqlite3.connect(temp_path)
                    cursor = conn.cursor()
                    cursor.execute("SELECT COUNT(*) FROM urls")
                    count = cursor.fetchone()[0]
                    conn.close()
                    
                    logger.info(f"✓ Successfully copied History database with {count} URLs")
                    return temp_path
                except sqlite3.Error as e:
                    logger.warning(f"Copied file is not a valid SQLite database: {e}")
                    os.unlink(temp_path)
            else:
                os.unlink(temp_path)
                
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            if os.path.exists(temp_path):
                os.unlink(temp_path)
            continue
    
    logger.error("Could not copy History database from any location")
    return None


def verify_selective_deletion(history_path: str, initial_state: Optional[Dict]) -> Dict[str, Any]:
    """
    Verify selective history deletion using SQLite queries.
    
    Args:
        history_path: Path to History database
        initial_state: Initial state dict or None
        
    Returns:
        Verification result dict
    """
    try:
        conn = sqlite3.connect(history_path)
        cursor = conn.cursor()
        
        # Query for shopping URLs (should be 0)
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%example-shopping-site%'")
        shopping_count = cursor.fetchone()[0]
        
        cursor.execute("SELECT url FROM urls WHERE url LIKE '%example-shopping-site%'")
        shopping_urls = [row[0] for row in cursor.fetchall()]
        
        # Query for news URLs (should be >= 2)
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%news-website%'")
        news_count = cursor.fetchone()[0]
        
        # Query for work URLs (should be >= 2)
        cursor.execute("SELECT COUNT(*) FROM urls WHERE url LIKE '%work-related%'")
        work_count = cursor.fetchone()[0]
        
        # Get total URL count
        cursor.execute("SELECT COUNT(*) FROM urls")
        total_count = cursor.fetchone()[0]
        
        conn.close()
        
        # Evaluate criteria
        criteria = {}
        
        # Criterion 1: Shopping URLs deleted
        criteria['shopping_deleted'] = (shopping_count == 0)
        logger.info(f"✓ Criterion 1 - Shopping URLs deleted: {criteria['shopping_deleted']} (count: {shopping_count})")
        
        # Criterion 2: News URLs preserved
        criteria['news_preserved'] = (news_count >= 2)
        logger.info(f"✓ Criterion 2 - News URLs preserved: {criteria['news_preserved']} (count: {news_count})")
        
        # Criterion 3: Work URLs preserved
        criteria['work_preserved'] = (work_count >= 2)
        logger.info(f"✓ Criterion 3 - Work URLs preserved: {criteria['work_preserved']} (count: {work_count})")
        
        # Criterion 4: Correct deletion count (exactly 2 entries removed)
        if initial_state:
            initial_total = initial_state.get('total_count', 0)
            expected_final = initial_total - 2
            deletion_count_ok = (total_count == expected_final)
            entries_deleted = initial_total - total_count
        else:
            # Without initial state, just check that we have reasonable counts
            deletion_count_ok = (shopping_count == 0 and news_count >= 2 and work_count >= 2)
            entries_deleted = "unknown"
        
        criteria['deletion_count_accurate'] = deletion_count_ok
        logger.info(f"✓ Criterion 4 - Deletion count accurate: {criteria['deletion_count_accurate']} (deleted: {entries_deleted})")
        
        # Criterion 5: Database integrity (no corruption, schema intact)
        try:
            conn = sqlite3.connect(history_path)
            cursor = conn.cursor()
            
            # Check schema is intact
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='urls'")
            has_urls_table = cursor.fetchone() is not None
            
            # Check visits table exists
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='visits'")
            has_visits_table = cursor.fetchone() is not None
            
            conn.close()
            
            db_integrity_ok = has_urls_table and has_visits_table
        except Exception as e:
            logger.error(f"Database integrity check failed: {e}")
            db_integrity_ok = False
        
        criteria['database_integrity'] = db_integrity_ok
        logger.info(f"✓ Criterion 5 - Database integrity: {criteria['database_integrity']}")
        
        # Calculate score
        criteria_met = sum(criteria.values())
        score = int((criteria_met / 5) * 100)
        passed = score >= 80  # Need at least 4/5 criteria
        
        # Generate feedback
        feedback_parts = []
        feedback_parts.append(f"Verification Results: {criteria_met}/5 criteria met\n")
        
        feedback_parts.append(f"{'✓' if criteria['shopping_deleted'] else '✗'} Shopping URLs deleted: {shopping_count} remaining (expected 0)")
        if shopping_count > 0:
            feedback_parts.append(f"  Found: {', '.join(shopping_urls[:3])}")
        
        feedback_parts.append(f"{'✓' if criteria['news_preserved'] else '✗'} News URLs preserved: {news_count} found (expected >= 2)")
        
        feedback_parts.append(f"{'✓' if criteria['work_preserved'] else '✗'} Work URLs preserved: {work_count} found (expected >= 2)")
        
        feedback_parts.append(f"{'✓' if criteria['deletion_count_accurate'] else '✗'} Deletion count: {entries_deleted} entries removed")
        
        feedback_parts.append(f"{'✓' if criteria['database_integrity'] else '✗'} Database integrity: {'OK' if db_integrity_ok else 'COMPROMISED'}")
        
        feedback_parts.append(f"\n{'='*50}")
        feedback_parts.append(f"Score: {score}%")
        feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
        
        if passed:
            feedback_parts.append("\nExcellent work! You successfully:")
            feedback_parts.append("  • Navigated to chrome://history")
            feedback_parts.append("  • Searched for shopping-related entries")
            feedback_parts.append("  • Selectively deleted only the target URLs")
            feedback_parts.append("  • Preserved all other history entries")
        else:
            feedback_parts.append("\nTask incomplete. You should:")
            if not criteria['shopping_deleted']:
                feedback_parts.append("  • Delete ALL shopping-related URLs")
            if not criteria['news_preserved']:
                feedback_parts.append("  • Preserve news website history")
            if not criteria['work_preserved']:
                feedback_parts.append("  • Preserve work-related history")
            if not criteria['deletion_count_accurate']:
                feedback_parts.append("  • Delete exactly 2 entries, not more")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria": criteria,
                "counts": {
                    "shopping": shopping_count,
                    "news": news_count,
                    "work": work_count,
                    "total": total_count
                },
                "initial_state": initial_state
            }
        }
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database query error: {str(e)}"
        }


def cleanup_temp_files(history_path: str):
    """Clean up temporary files"""
    try:
        if history_path and os.path.exists(history_path):
            os.unlink(history_path)
            logger.info("Cleaned up temporary History database")
    except Exception as e:
        logger.warning(f"Could not clean up temp files: {e}")
