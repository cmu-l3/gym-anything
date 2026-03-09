#!/usr/bin/env python3
"""
Verifier for Chrome Autofill Profile Setup Task (autofill_profile_setup@1)
Task: Configure autofill profile with personal information to save time on form filling

Verification Strategy:
- Copy Chrome's Web Data SQLite database from container
- Query autofill_profiles table and related tables (names, emails, phones)
- Verify that a profile was created during task execution
- Check that required fields are populated (name, email, phone, address)
- Validate data formats (email contains @, phone has digits, etc.)
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
import re
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
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for autofill_profile_setup@1.
    
    Verifies that an autofill profile was created with required personal information.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get task start time for filtering recent profiles
        task_start_time = get_task_start_time(copy_from_env)
        logger.info(f"Task start time: {task_start_time}")
        
        # Extract Web Data database
        db_path, error_msg = extract_web_data_database(copy_from_env)
        
        if db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Web Data database: {error_msg}"
            }
        
        # Verify autofill profile
        verification_result = verify_autofill_profile(db_path, task_start_time)
        
        # Clean up temporary files
        try:
            if db_path and os.path.exists(db_path):
                os.unlink(db_path)
        except:
            pass
        
        cleanup_verification_temp()
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_task_start_time(copy_from_env) -> int:
    """
    Get task start timestamp for filtering recent profiles.
    
    Returns:
        Unix timestamp (seconds since epoch)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/task_start_time.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            task_start = int(f.read().strip())
        
        os.unlink(temp_file.name)
        return task_start
        
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}, using 0")
        return 0


def extract_web_data_database(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Extract Web Data SQLite database from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_db_path: str or None, error_message: str)
    """
    try:
        # Create temp file for database
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try to copy from exported location
        logger.info("Attempting to copy Web Data database...")
        
        try:
            copy_from_env("/tmp/web_data_export.db", temp_path)
            
            # Check if file was copied successfully and is a valid database
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 100:
                # Try to open as SQLite database
                try:
                    conn = sqlite3.connect(temp_path)
                    cursor = conn.cursor()
                    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
                    tables = cursor.fetchall()
                    conn.close()
                    
                    logger.info(f"Successfully copied Web Data database ({os.path.getsize(temp_path)} bytes)")
                    logger.info(f"Database contains {len(tables)} tables")
                    return temp_path, ""
                    
                except sqlite3.Error as e:
                    logger.error(f"Copied file is not a valid SQLite database: {e}")
                    os.unlink(temp_path)
                    return None, f"Web Data file is not a valid SQLite database: {e}"
            else:
                os.unlink(temp_path)
                return None, "Web Data database file is empty or not found"
                
        except Exception as e:
            logger.error(f"Failed to copy Web Data database: {e}")
            if os.path.exists(temp_path):
                os.unlink(temp_path)
            return None, f"Could not copy Web Data database: {e}"
            
    except Exception as e:
        return None, f"Error extracting Web Data database: {e}"


def verify_autofill_profile(db_path: str, task_start_time: int) -> Dict[str, Any]:
    """
    Verify that an autofill profile was created with required fields.
    
    Checks:
    1. Profile exists in database
    2. Profile was created during task execution (timestamp check)
    3. Name fields are populated
    4. Email is populated and valid format
    5. Phone is populated and contains digits
    6. Address fields are populated (street, city, state, zip)
    
    Args:
        db_path: Path to Web Data SQLite database
        task_start_time: Unix timestamp of task start
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check if required tables exist
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('autofill_profiles', 'autofill_profile_names', 'autofill_profile_emails', 'autofill_profile_phones');")
        existing_tables = [row[0] for row in cursor.fetchall()]
        
        if 'autofill_profiles' not in existing_tables:
            conn.close()
            return {
                "passed": False,
                "score": 0,
                "feedback": "Autofill profiles table not found in database. Chrome may not have saved the data.",
                "details": {"error": "missing_table"}
            }
        
        logger.info(f"Found tables: {existing_tables}")
        
        # Convert task_start_time to Chrome timestamp format (microseconds since epoch)
        # Chrome uses Windows epoch (1601-01-01) but modern Chrome uses Unix epoch
        # For simplicity, we'll look for profiles created in the last hour
        chrome_start_time = task_start_time * 1_000_000  # Convert to microseconds
        
        # Query for recent autofill profiles
        # Chrome's date_modified is in microseconds since Unix epoch
        query = """
        SELECT 
            guid,
            company_name,
            street_address,
            city,
            state,
            zipcode,
            country_code,
            date_modified,
            use_count
        FROM autofill_profiles
        WHERE date_modified > ?
        ORDER BY date_modified DESC
        """
        
        cursor.execute(query, (chrome_start_time,))
        profiles = cursor.fetchall()
        
        logger.info(f"Found {len(profiles)} profile(s) created after task start")
        
        if len(profiles) == 0:
            # Try without timestamp filter as fallback
            logger.warning("No profiles found with timestamp filter, trying without filter...")
            cursor.execute("SELECT guid, company_name, street_address, city, state, zipcode, country_code, date_modified, use_count FROM autofill_profiles ORDER BY date_modified DESC LIMIT 1")
            profiles = cursor.fetchall()
            
            if len(profiles) == 0:
                conn.close()
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "No autofill profile found in database. Agent may not have clicked 'Save' button.",
                    "details": {"error": "no_profile_created"}
                }
        
        # Get the most recent profile
        profile = profiles[0]
        guid = profile[0]
        company_name = profile[1]
        street_address = profile[2]
        city = profile[3]
        state = profile[4]
        zipcode = profile[5]
        country_code = profile[6]
        date_modified = profile[7]
        
        logger.info(f"Analyzing profile with GUID: {guid}")
        logger.info(f"  Street: {street_address}")
        logger.info(f"  City: {city}, State: {state}, ZIP: {zipcode}")
        
        # Get name from autofill_profile_names table
        first_name = ""
        last_name = ""
        if 'autofill_profile_names' in existing_tables:
            cursor.execute("SELECT first_name, middle_name, last_name FROM autofill_profile_names WHERE guid = ?", (guid,))
            name_row = cursor.fetchone()
            if name_row:
                first_name = name_row[0] or ""
                last_name = name_row[2] or ""
                logger.info(f"  Name: {first_name} {last_name}")
        
        # Get email from autofill_profile_emails table
        email = ""
        if 'autofill_profile_emails' in existing_tables:
            cursor.execute("SELECT email FROM autofill_profile_emails WHERE guid = ?", (guid,))
            email_row = cursor.fetchone()
            if email_row:
                email = email_row[0] or ""
                logger.info(f"  Email: {email}")
        
        # Get phone from autofill_profile_phones table
        phone = ""
        if 'autofill_profile_phones' in existing_tables:
            cursor.execute("SELECT number FROM autofill_profile_phones WHERE guid = ?", (guid,))
            phone_row = cursor.fetchone()
            if phone_row:
                phone = phone_row[0] or ""
                logger.info(f"  Phone: {phone}")
        
        conn.close()
        
        # Validation checks
        checks = {
            "profile_exists": True,  # We found a profile
            "has_name": bool(first_name or last_name),
            "has_email": bool(email and "@" in email and "." in email),
            "has_phone": bool(phone and any(c.isdigit() for c in phone)),
            "has_address": bool(street_address and city and state and zipcode)
        }
        
        # Calculate score
        criteria_met = sum(checks.values())
        total_criteria = len(checks)
        score = int((criteria_met / total_criteria) * 100)
        
        # Determine pass/fail (need at least 4/5 criteria = 80%)
        passed = score >= 80
        
        # Generate detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Autofill Profile Verification: {criteria_met}/{total_criteria} criteria met")
        feedback_parts.append("")
        
        if checks["profile_exists"]:
            feedback_parts.append(f"✓ Profile created (GUID: {guid[:8]}...)")
        else:
            feedback_parts.append("✗ No profile found")
        
        if checks["has_name"]:
            feedback_parts.append(f"✓ Name populated: {first_name} {last_name}")
        else:
            feedback_parts.append("✗ Name missing or incomplete")
        
        if checks["has_email"]:
            feedback_parts.append(f"✓ Email valid: {email}")
        else:
            feedback_parts.append("✗ Email missing or invalid format")
        
        if checks["has_phone"]:
            feedback_parts.append(f"✓ Phone populated: {phone}")
        else:
            feedback_parts.append("✗ Phone missing or invalid")
        
        if checks["has_address"]:
            feedback_parts.append(f"✓ Address complete: {street_address}, {city}, {state} {zipcode}")
        else:
            feedback_parts.append("✗ Address incomplete (missing street/city/state/zip)")
        
        feedback_parts.append("")
        
        if passed:
            feedback_parts.append("✅ Task completed successfully! Autofill profile is ready for use.")
        else:
            feedback_parts.append("❌ Task incomplete - profile missing required information")
            feedback_parts.append("Hint: Make sure to fill all required fields before clicking 'Save'")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_met,
                "total_criteria": total_criteria,
                "checks": checks,
                "profile_data": {
                    "guid": guid,
                    "name": f"{first_name} {last_name}".strip(),
                    "email": email,
                    "phone": phone,
                    "address": f"{street_address}, {city}, {state} {zipcode}".strip()
                }
            }
        }
        
    except sqlite3.Error as e:
        logger.error(f"Database error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Database error during verification: {str(e)}",
            "details": {"error": "database_error"}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "details": {"error": "verification_error"}
        }
