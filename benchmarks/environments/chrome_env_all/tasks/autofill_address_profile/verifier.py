#!/usr/bin/env python3
"""
Verifier for Chrome AutoFill Address Profile Creation Task (autofill_address_profile@1)
Task: Create a complete AutoFill address profile with Sarah Mitchell's information

Verification Strategy:
- Copy Chrome's Web Data SQLite database from container
- Query autofill_profiles table for new entries
- Join with autofill_profile_names, autofill_profile_emails, autofill_profile_phones tables
- Verify all 6 criteria:
  1. Profile exists (created during task window)
  2. Name correct (Sarah Mitchell)
  3. Address valid (742 Evergreen Terrace, Springfield, IL 62704)
  4. Email correct (sarah.mitchell@example.com)
  5. Phone correct (217-555-0147)
  6. Data consistent (ZIP matches city/state)
"""

import logging
import sys
import os
import sqlite3
import tempfile
from pathlib import Path
from datetime import datetime

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
    Main verification function for autofill_address_profile@1.
    
    Verifies that a complete AutoFill address profile was created with:
    - Name: Sarah Mitchell
    - Address: 742 Evergreen Terrace, Springfield, IL 62704
    - Phone: 217-555-0147
    - Email: sarah.mitchell@example.com
    
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

    try:
        # Get task start time for timestamp validation
        task_start_time = get_task_start_time(copy_from_env)
        logger.info(f"Task start time: {task_start_time}")
        
        # Copy Web Data database from container
        db_path, error_msg = copy_web_data_database(copy_from_env)
        
        if db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Web Data database: {error_msg}"
            }
        
        logger.info(f"Web Data database copied to: {db_path}")
        
        # Verify AutoFill profile
        result = verify_autofill_profile(db_path, task_start_time)
        
        # Cleanup temporary files
        cleanup_temp_files(db_path)
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


def get_task_start_time(copy_from_env):
    """
    Retrieve task start time from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        int: Task start timestamp in seconds since epoch (0 if not found)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/autofill_task_start_time.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            task_start = int(f.read().strip())
        
        os.unlink(temp_file.name)
        return task_start
        
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}, using 0")
        return 0


def copy_web_data_database(copy_from_env):
    """
    Copy Web Data SQLite database from container to host.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (db_path: str or None, error_message: str)
    """
    # Try multiple possible locations
    container_paths = [
        "/tmp/web_data_export.db",
        "/home/ga/.config/google-chrome-cdp/Default/Web Data",
        "/home/ga/.config/google-chrome/Default/Web Data",
    ]
    
    for container_path in container_paths:
        try:
            temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
            temp_db.close()
            
            logger.info(f"Trying to copy from: {container_path}")
            copy_from_env(container_path, temp_db.name)
            
            # Check if file was copied successfully and is not empty
            if os.path.exists(temp_db.name) and os.path.getsize(temp_db.name) > 0:
                logger.info(f"✓ Successfully copied Web Data from: {container_path}")
                
                # Quick validation: try to open as SQLite database
                try:
                    conn = sqlite3.connect(temp_db.name)
                    cursor = conn.cursor()
                    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
                    tables = [row[0] for row in cursor.fetchall()]
                    conn.close()
                    
                    logger.info(f"Database contains {len(tables)} tables")
                    
                    if 'autofill_profiles' in tables:
                        return temp_db.name, ""
                    else:
                        logger.warning("Database doesn't contain autofill_profiles table")
                        os.unlink(temp_db.name)
                        continue
                        
                except sqlite3.Error as e:
                    logger.warning(f"Database file is corrupted: {e}")
                    os.unlink(temp_db.name)
                    continue
            else:
                logger.debug(f"File not found or empty at: {container_path}")
                os.unlink(temp_db.name)
                
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            if os.path.exists(temp_db.name):
                os.unlink(temp_db.name)
            continue
    
    return None, "Web Data database not found in any known location"


def verify_autofill_profile(db_path, task_start_time):
    """
    Verify AutoFill profile was correctly created.
    
    Checks 6 criteria:
    1. Profile exists (created after task start)
    2. Name correct (Sarah Mitchell)
    3. Address valid (742 Evergreen Terrace, Springfield, IL 62704)
    4. Email correct (sarah.mitchell@example.com)
    5. Phone correct (217-555-0147)
    6. Data consistent (ZIP 62704 matches Springfield, IL)
    
    Args:
        db_path: Path to Web Data SQLite database
        task_start_time: Task start timestamp (seconds since epoch)
        
    Returns:
        Dict with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Convert task start time to Chrome's timestamp format (microseconds since Windows epoch)
        # Chrome timestamps are microseconds since January 1, 1601
        # Unix epoch (Jan 1, 1970) is 11644473600 seconds after Windows epoch
        # So: chrome_time = (unix_time + 11644473600) * 1000000
        chrome_task_start = (task_start_time + 11644473600) * 1000000
        
        logger.info(f"Task start time (Chrome format): {chrome_task_start}")
        
        # Criterion 1: Check if profile exists (created during task)
        cursor.execute("""
            SELECT guid, street_address, dependent_locality, city, state, zipcode, 
                   sorting_code, country_code, date_modified, use_count
            FROM autofill_profiles
            WHERE date_modified >= ?
            ORDER BY date_modified DESC
            LIMIT 10
        """, (chrome_task_start,))
        
        profiles = cursor.fetchall()
        
        if not profiles:
            # Try without timestamp filter to see if any profiles exist
            cursor.execute("""
                SELECT guid, street_address, city, state, zipcode, country_code, date_modified
                FROM autofill_profiles
                ORDER BY date_modified DESC
                LIMIT 5
            """)
            all_profiles = cursor.fetchall()
            
            logger.info(f"No profiles found with timestamp filter. All profiles: {len(all_profiles)}")
            
            if all_profiles:
                # Use the most recent profile regardless of timestamp
                logger.warning("Using most recent profile (timestamp filter may have failed)")
                profile = all_profiles[0]
                criteria_met += 0.5  # Partial credit
                feedback_parts.append("⚠ Profile found but timestamp uncertain")
            else:
                feedback_parts.append("✗ No AutoFill profile found in database")
                conn.close()
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "\n".join(feedback_parts) + "\n\nNo AutoFill address profile was created."
                }
        else:
            profile = profiles[0]
            criteria_met += 1
            feedback_parts.append("✓ Profile exists")
            logger.info(f"Found {len(profiles)} profile(s) created during task")
        
        guid, street, dependent, city, state, zipcode, sorting, country, date_mod, use_count = profile
        
        logger.info(f"Profile details: GUID={guid}, Address={street}, City={city}, State={state}, ZIP={zipcode}")
        
        # Criterion 2: Validate name fields
        cursor.execute("""
            SELECT first_name, middle_name, last_name, full_name
            FROM autofill_profile_names
            WHERE guid = ?
        """, (guid,))
        
        name_data = cursor.fetchone()
        
        if name_data:
            first_name, middle_name, last_name, full_name = name_data
            logger.info(f"Name: {first_name} {middle_name or ''} {last_name}")
            
            # Check if name matches Sarah Mitchell (case-insensitive, flexible)
            first_match = first_name and 'sarah' in first_name.lower()
            last_match = last_name and 'mitchell' in last_name.lower()
            
            if first_match and last_match:
                criteria_met += 1
                feedback_parts.append(f"✓ Name correct: {first_name} {last_name}")
            else:
                feedback_parts.append(f"✗ Name incorrect: {first_name or ''} {last_name or ''} (expected: Sarah Mitchell)")
        else:
            feedback_parts.append("✗ Name not found in database")
        
        # Criterion 3: Validate address fields
        # Expected: 742 Evergreen Terrace, Springfield, IL 62704
        
        street_valid = street and '742' in street and 'evergreen' in street.lower() and 'terrace' in street.lower()
        city_valid = city and city.lower() == 'springfield'
        state_valid = state and state.upper() in ['IL', 'ILLINOIS']
        zip_valid = zipcode and zipcode.strip() == '62704'
        
        address_valid = street_valid and city_valid and state_valid and zip_valid
        
        if address_valid:
            criteria_met += 1
            feedback_parts.append(f"✓ Address correct: {street}, {city}, {state} {zipcode}")
        else:
            address_parts = []
            if not street_valid:
                address_parts.append(f"street: '{street}' (expected: 742 Evergreen Terrace)")
            if not city_valid:
                address_parts.append(f"city: '{city}' (expected: Springfield)")
            if not state_valid:
                address_parts.append(f"state: '{state}' (expected: IL)")
            if not zip_valid:
                address_parts.append(f"ZIP: '{zipcode}' (expected: 62704)")
            
            feedback_parts.append(f"✗ Address incorrect: {', '.join(address_parts)}")
        
        # Criterion 4: Validate email
        cursor.execute("""
            SELECT email
            FROM autofill_profile_emails
            WHERE guid = ?
        """, (guid,))
        
        email_data = cursor.fetchone()
        
        if email_data:
            email = email_data[0]
            logger.info(f"Email: {email}")
            
            if email and 'sarah.mitchell@example.com' in email.lower():
                criteria_met += 1
                feedback_parts.append(f"✓ Email correct: {email}")
            else:
                feedback_parts.append(f"✗ Email incorrect: {email} (expected: sarah.mitchell@example.com)")
        else:
            feedback_parts.append("✗ Email not found")
        
        # Criterion 5: Validate phone
        cursor.execute("""
            SELECT number
            FROM autofill_profile_phones
            WHERE guid = ?
        """, (guid,))
        
        phone_data = cursor.fetchone()
        
        if phone_data:
            phone = phone_data[0]
            logger.info(f"Phone: {phone}")
            
            # Normalize phone number (remove non-digits)
            phone_normalized = ''.join(c for c in phone if c.isdigit())
            expected_normalized = '2175550147'
            
            if phone_normalized == expected_normalized:
                criteria_met += 1
                feedback_parts.append(f"✓ Phone correct: {phone}")
            else:
                feedback_parts.append(f"✗ Phone incorrect: {phone} (expected: 217-555-0147)")
        else:
            feedback_parts.append("✗ Phone not found")
        
        # Criterion 6: Data consistency check
        # ZIP 62704 should correspond to Springfield, IL
        consistency_valid = (
            zipcode == '62704' and
            city and city.lower() == 'springfield' and
            state and state.upper() in ['IL', 'ILLINOIS']
        )
        
        if consistency_valid:
            criteria_met += 1
            feedback_parts.append("✓ Data consistent (ZIP matches city/state)")
        else:
            feedback_parts.append("⚠ Data consistency issue (ZIP doesn't match city/state)")
        
        conn.close()
        
    except sqlite3.Error as e:
        logger.error(f"Database error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database error during verification: {str(e)}"
        }
    
    # Calculate final score
    # 6 criteria total, need 5+ to pass (85%)
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 5
    
    # Build final feedback
    feedback = f"AutoFill Profile Verification: {criteria_met}/{total_criteria} criteria met\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\n✅ AutoFill address profile successfully created with correct information!"
    else:
        feedback += f"\n\n❌ AutoFill profile incomplete or incorrect. Need at least 5/6 criteria (currently {criteria_met}/6)."
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "profile_found": criteria_met >= 1
        }
    }


def cleanup_temp_files(db_path):
    """Clean up temporary database file"""
    try:
        if db_path and os.path.exists(db_path):
            os.unlink(db_path)
            logger.info("Cleaned up temporary database file")
    except Exception as e:
        logger.warning(f"Could not clean up temp file: {e}")
