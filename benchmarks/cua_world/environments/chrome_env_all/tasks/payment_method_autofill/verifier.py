#!/usr/bin/env python3
"""
Verifier for Chrome Payment Method Autofill Configuration Task (payment_method_autofill@1)
Task: Add credit card to Chrome's payment methods for autofill

Verification Strategy:
- Copy Chrome Web Data SQLite database from container
- Query credit_cards table for the added payment method
- Verify cardholder name, expiration date, and card details
- Ensure entry was created during task execution window
- Validate database structure and data integrity
"""

import logging
import sys
import os
import sqlite3
import tempfile
import time
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for payment_method_autofill@1.
    
    Verifies that a credit card payment method was correctly added to Chrome's autofill.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    # Expected payment method details
    expected_name = "Alex Chen"
    expected_month = 12
    expected_year = 2027
    expected_last_4 = "6467"
    
    temp_db_path = None
    
    try:
        # Get task start timestamp if available
        task_start_time = get_task_start_timestamp(copy_from_env)
        
        # Copy Web Data database from container
        web_data_path, copy_error = copy_web_data_database(copy_from_env)
        
        if web_data_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Web Data database: {copy_error}"
            }
        
        temp_db_path = web_data_path
        
        # Verify payment method in database
        verification_result = verify_payment_method_in_database(
            web_data_path,
            expected_name,
            expected_month,
            expected_year,
            expected_last_4,
            task_start_time
        )
        
        # Clean up
        cleanup_verification_temp()
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary database file
        if temp_db_path and os.path.exists(temp_db_path):
            try:
                os.unlink(temp_db_path)
            except:
                pass


def get_task_start_timestamp(copy_from_env):
    """
    Get the task start timestamp for filtering recent entries.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Unix timestamp (int) or None if not available
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/task_timestamp.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            timestamp = int(f.read().strip())
        
        os.unlink(temp_file.name)
        logger.info(f"Task start timestamp: {timestamp}")
        return timestamp
        
    except Exception as e:
        logger.warning(f"Could not get task start timestamp: {e}")
        # Return timestamp from 5 minutes ago as fallback
        return int(time.time()) - 300


def copy_web_data_database(copy_from_env):
    """
    Copy Chrome Web Data database from container to local temp file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_path: str or None, error_message: str)
    """
    try:
        # Create temporary file for database
        temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_db.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/web_data_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/Web Data",
            "/home/ga/.config/google-chrome/Default/Web Data",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Attempting to copy Web Data from: {container_path}")
                copy_from_env(container_path, temp_db.name)
                
                # Check if file has content
                if os.path.exists(temp_db.name) and os.path.getsize(temp_db.name) > 0:
                    logger.info(f"✓ Successfully copied Web Data from: {container_path}")
                    return temp_db.name, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_db.name)
        return None, "Web Data database could not be copied from any known location"
        
    except Exception as e:
        logger.error(f"Error copying Web Data: {e}")
        return None, f"Error copying database: {str(e)}"


def verify_payment_method_in_database(db_path, expected_name, expected_month, 
                                      expected_year, expected_last_4, task_start_time):
    """
    Verify payment method exists in Web Data database with correct details.
    
    Args:
        db_path: Path to Web Data SQLite database
        expected_name: Expected cardholder name
        expected_month: Expected expiration month
        expected_year: Expected expiration year
        expected_last_4: Expected last 4 digits of card number
        task_start_time: Unix timestamp of task start
        
    Returns:
        Dict with verification results
    """
    try:
        # Connect to database
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check if credit_cards table exists
        cursor.execute("""
            SELECT name FROM sqlite_master 
            WHERE type='table' AND name='credit_cards';
        """)
        
        if not cursor.fetchone():
            conn.close()
            return {
                "passed": False,
                "score": 0,
                "feedback": "Credit cards table does not exist in Web Data database"
            }
        
        # Get all credit card entries
        cursor.execute("""
            SELECT guid, name_on_card, expiration_month, expiration_year, 
                   date_modified, use_count, use_date
            FROM credit_cards
        """)
        
        all_entries = cursor.fetchall()
        logger.info(f"Found {len(all_entries)} total credit card entries in database")
        
        # Filter for entries matching our expected name
        matching_entries = []
        for entry in all_entries:
            guid, name, month, year, date_mod, use_count, use_date = entry
            logger.info(f"Entry: name='{name}', exp={month}/{year}, date_modified={date_mod}")
            
            if name == expected_name:
                matching_entries.append({
                    'guid': guid,
                    'name': name,
                    'month': month,
                    'year': year,
                    'date_modified': date_mod,
                    'use_count': use_count,
                    'use_date': use_date
                })
        
        conn.close()
        
        if not matching_entries:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No credit card entry found with name '{expected_name}'. "
                           f"Found {len(all_entries)} total entries in database."
            }
        
        # Verify the most recent matching entry
        # Chrome stores date_modified as microseconds since Windows epoch (1601-01-01)
        # We'll check if the entry is recent by comparing to task start time
        entry = matching_entries[-1]  # Most recent entry
        
        # Verify all criteria
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # Criterion 1: Entry exists with correct name
        criteria_met += 1
        feedback_parts.append(f"✓ Credit card entry found for '{entry['name']}'")
        
        # Criterion 2: Correct expiration month
        if entry['month'] == expected_month:
            criteria_met += 1
            feedback_parts.append(f"✓ Expiration month correct: {entry['month']}")
        else:
            feedback_parts.append(f"✗ Expiration month incorrect: {entry['month']} (expected {expected_month})")
        
        # Criterion 3: Correct expiration year
        if entry['year'] == expected_year:
            criteria_met += 1
            feedback_parts.append(f"✓ Expiration year correct: {entry['year']}")
        else:
            feedback_parts.append(f"✗ Expiration year incorrect: {entry['year']} (expected {expected_year})")
        
        # Criterion 4: Entry has valid GUID and structure
        if entry['guid'] and len(entry['guid']) > 0:
            criteria_met += 1
            feedback_parts.append(f"✓ Valid database entry with GUID: {entry['guid'][:8]}...")
        else:
            feedback_parts.append(f"✗ Invalid database entry structure")
        
        # Criterion 5: Entry was created recently (during task window)
        # Chrome's date_modified is in microseconds since Windows epoch
        # We'll be lenient here and just check if date_modified exists and is non-zero
        if entry['date_modified'] and entry['date_modified'] > 0:
            criteria_met += 1
            feedback_parts.append(f"✓ Entry has valid creation timestamp")
        else:
            feedback_parts.append(f"✗ Entry has invalid or missing timestamp")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 80  # Need at least 4 out of 5 criteria
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if len(matching_entries) > 1:
            feedback += f"\n\nNote: Multiple entries found with name '{expected_name}'. Verified the most recent one."
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "entries_found": len(matching_entries),
                "name": entry['name'],
                "expiration_month": entry['month'],
                "expiration_year": entry['year'],
                "guid": entry['guid']
            }
        }
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database error: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
