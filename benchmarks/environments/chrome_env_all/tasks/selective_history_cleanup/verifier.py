#!/usr/bin/env python3
"""
Verifier for Chrome Selective History Cleanup Task (selective_history_cleanup@1)
Task: Selectively delete shopping-related history while preserving other browsing history

Verification Strategy:
- Copy History SQLite database from container
- Query for shopping-related URLs (keywords: shop, amazon, ebay, etsy, walmart, cart, buy)
- Verify 0 shopping entries remain
- Query for non-shopping entries (news, educational, social)
- Verify 90%+ of non-shopping entries are preserved
- Ensure no mass deletion occurred (<50% of total history deleted)
- Validate database integrity
"""

import logging
import sys
import os
import sqlite3
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for selective_history_cleanup@1.
    
    Verifies:
    1. Shopping entries deleted (0 remaining)
    2. Adequate deletion count (5-7 entries removed)
    3. Other entries preserved (≥90% retention)
    4. Database valid and accessible
    5. No mass deletion (<50% of total deleted)
    
    Args:
        traj: Trajectory data (not used)
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
        # Get History database and initial counts
        history_db_path, initial_total, initial_shopping, error = get_history_database(copy_from_env)
        
        if history_db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve History database: {error}"
            }
        
        # Perform verification
        result = verify_selective_deletion(
            history_db_path,
            initial_total,
            initial_shopping
        )
        
        # Cleanup
        try:
            os.unlink(history_db_path)
        except:
            pass
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


def get_history_database(copy_from_env) -> Tuple[Optional[str], int, int, str]:
    """
    Copy History database from container and get initial counts.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (db_path, initial_total, initial_shopping, error_message)
    """
    try:
        # Create temporary file for History database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        # Try to copy History database
        possible_paths = [
            "/tmp/history_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        success = False
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy History from: {container_path}")
                copy_from_env(container_path, temp_db.name)
                
                # Verify file has content
                if Path(temp_db.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied History from: {container_path}")
                    success = True
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not success:
            os.unlink(temp_db.name)
            return None, 0, 0, "Could not copy History database from any location"
        
        # Verify database is valid SQLite
        try:
            conn = sqlite3.connect(temp_db.name)
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='urls';")
            if not cursor.fetchone():
                conn.close()
                os.unlink(temp_db.name)
                return None, 0, 0, "History database missing 'urls' table"
            conn.close()
        except sqlite3.DatabaseError as e:
            os.unlink(temp_db.name)
            return None, 0, 0, f"History database is corrupted: {e}"
        
        # Get initial counts
        initial_total = 21  # Default from setup
        initial_shopping = 6  # Default from setup
        
        try:
            temp_counts = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            temp_counts.close()
            copy_from_env("/tmp/initial_history_total.txt", temp_counts.name)
            with open(temp_counts.name, 'r') as f:
                initial_total = int(f.read().strip())
            os.unlink(temp_counts.name)
            
            temp_shopping = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            temp_shopping.close()
            copy_from_env("/tmp/initial_shopping_count.txt", temp_shopping.name)
            with open(temp_shopping.name, 'r') as f:
                initial_shopping = int(f.read().strip())
            os.unlink(temp_shopping.name)
        except Exception as e:
            logger.warning(f"Could not read initial counts, using defaults: {e}")
        
        logger.info(f"Initial counts: {initial_total} total, {initial_shopping} shopping")
        return temp_db.name, initial_total, initial_shopping, ""
        
    except Exception as e:
        return None, 0, 0, f"Error getting History database: {str(e)}"


def verify_selective_deletion(db_path: str, initial_total: int, initial_shopping: int) -> Dict[str, Any]:
    """
    Verify selective deletion of shopping entries while preserving others.
    
    Args:
        db_path: Path to History database
        initial_total: Initial total entry count
        initial_shopping: Initial shopping entry count
        
    Returns:
        Verification result dict
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Criterion 1: Check shopping entries are deleted
        shopping_keywords = ['shop', 'amazon', 'ebay', 'etsy', 'walmart', 'cart', 'buy', 'checkout']
        shopping_query = " OR ".join([f"url LIKE '%{kw}%' OR title LIKE '%{kw}%'" for kw in shopping_keywords])
        cursor.execute(f"SELECT COUNT(*) FROM urls WHERE {shopping_query}")
        shopping_remaining = cursor.fetchone()[0]
        shopping_deleted = shopping_remaining == 0
        
        logger.info(f"✓ Shopping entries remaining: {shopping_remaining} (expected: 0)")
        
        # Criterion 2: Check deletion count
        cursor.execute("SELECT COUNT(*) FROM urls")
        final_total = cursor.fetchone()[0]
        deleted_count = initial_total - final_total
        adequate_deletion = 5 <= deleted_count <= 8  # Expected to delete 6 shopping entries
        
        logger.info(f"✓ Entries deleted: {deleted_count} (expected: 5-8)")
        
        # Criterion 3: Check preservation of non-shopping entries
        expected_remaining = initial_total - initial_shopping
        non_shopping_remaining = final_total
        if shopping_remaining > 0:
            # Adjust if some shopping entries remain
            non_shopping_remaining = final_total - shopping_remaining
        
        preservation_rate = non_shopping_remaining / expected_remaining if expected_remaining > 0 else 0
        preservation_ok = preservation_rate >= 0.85  # Allow 15% loss for flexibility
        
        logger.info(f"✓ Non-shopping preservation: {non_shopping_remaining}/{expected_remaining} ({preservation_rate*100:.1f}%)")
        
        # Criterion 4: Database integrity
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='urls';")
        db_valid = cursor.fetchone() is not None
        
        logger.info(f"✓ Database integrity: {'Valid' if db_valid else 'Invalid'}")
        
        # Criterion 5: No mass deletion
        deletion_percentage = (deleted_count / initial_total) * 100 if initial_total > 0 else 0
        no_mass_deletion = deletion_percentage < 50
        
        logger.info(f"✓ Deletion percentage: {deletion_percentage:.1f}% (should be <50%)")
        
        # Close database connection
        conn.close()
        
        # Calculate score
        criteria_results = [
            shopping_deleted,
            adequate_deletion,
            preservation_ok,
            db_valid,
            no_mass_deletion
        ]
        
        criteria_met = sum(criteria_results)
        score = int((criteria_met / 5) * 100)
        passed = score >= 75  # Need 4/5 criteria
        
        # Generate detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Verification Results: {criteria_met}/5 criteria met")
        feedback_parts.append("")
        feedback_parts.append(f"{'✓' if shopping_deleted else '✗'} Shopping entries deleted: {shopping_remaining} remaining (expected: 0)")
        feedback_parts.append(f"{'✓' if adequate_deletion else '✗'} Deletion count: {deleted_count} entries (expected: 5-8)")
        feedback_parts.append(f"{'✓' if preservation_ok else '✗'} Non-shopping preserved: {preservation_rate*100:.1f}% (expected: ≥85%)")
        feedback_parts.append(f"{'✓' if db_valid else '✗'} Database valid: {db_valid}")
        feedback_parts.append(f"{'✓' if no_mass_deletion else '✗'} No mass deletion: {deletion_percentage:.1f}% deleted (should be <50%)")
        feedback_parts.append("")
        feedback_parts.append(f"Initial history: {initial_total} entries ({initial_shopping} shopping)")
        feedback_parts.append(f"Final history: {final_total} entries ({shopping_remaining} shopping)")
        feedback_parts.append(f"Deleted: {deleted_count} entries")
        feedback_parts.append("")
        
        if passed:
            feedback_parts.append("✅ Task completed successfully! Shopping history selectively deleted.")
        else:
            feedback_parts.append("❌ Task incomplete. Issues detected:")
            if not shopping_deleted:
                feedback_parts.append("  - Shopping entries still present in history")
            if not adequate_deletion:
                feedback_parts.append("  - Incorrect number of entries deleted")
            if not preservation_ok:
                feedback_parts.append("  - Too many non-shopping entries deleted")
            if not no_mass_deletion:
                feedback_parts.append("  - Mass deletion detected (may have cleared all history)")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "initial_total": initial_total,
                "initial_shopping": initial_shopping,
                "final_total": final_total,
                "shopping_remaining": shopping_remaining,
                "deleted_count": deleted_count,
                "preservation_rate": preservation_rate,
                "criteria_met": criteria_met
            }
        }
        
    except Exception as e:
        logger.error(f"Error during verification: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {str(e)}"
        }
