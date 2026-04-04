#!/usr/bin/env python3
"""
Verifier for Chrome Password Manager Manual Entry Task (password_manager_entry@1)
Task: Manually add a password entry via chrome://settings/passwords

Verification Strategy:
- Copy Chrome's Login Data SQLite database from container
- Query the logins table for the specific entry
- Verify: site URL, username, password presence, creation timestamp
- Note: Password is encrypted, so we only verify it's non-empty
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
    Main verification function for password_manager_entry@1.
    
    Verifies that a password entry was correctly added to Chrome's password manager.
    
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

    # Expected entry details
    expected_url = "https://example-testsite.com"
    expected_username = "testuser@example.com"
    expected_password_hint = "SecureP@ssw0rd!123"  # For feedback only, actual is encrypted

    try:
        # Get task start timestamp
        task_start_timestamp = get_task_start_time(copy_from_env)
        if task_start_timestamp is None:
            logger.warning("Could not retrieve task start time, using permissive check")
            task_start_timestamp = 0  # Very old timestamp to accept any entry
        
        # Get Login Data database
        login_db_path, error_msg = get_login_data_database(copy_from_env)
        if login_db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Login Data database: {error_msg}"
            }
        
        # Verify password entry exists
        verification_result = verify_password_entry(
            login_db_path,
            expected_url,
            expected_username,
            task_start_timestamp
        )
        
        # Cleanup
        try:
            if login_db_path and os.path.exists(login_db_path):
                os.unlink(login_db_path)
        except Exception as e:
            logger.warning(f"Could not clean up temp database: {e}")
        
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


def get_task_start_time(copy_from_env):
    """
    Retrieve the task start timestamp from the container.
    
    Returns:
        int: Unix timestamp in seconds, or None if not available
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        # Try to copy task start time
        try:
            copy_from_env("/tmp/task_start_time_export.txt", temp_file.name)
        except Exception as e:
            logger.warning(f"Could not copy task_start_time_export.txt: {e}")
            try:
                copy_from_env("/tmp/task_start_time.txt", temp_file.name)
            except Exception as e2:
                logger.warning(f"Could not copy task_start_time.txt either: {e2}")
                return None
        
        with open(temp_file.name, 'r') as f:
            timestamp_str = f.read().strip()
        
        timestamp = int(timestamp_str)
        logger.info(f"Task start timestamp: {timestamp} ({datetime.fromtimestamp(timestamp)})")
        return timestamp
        
    except Exception as e:
        logger.warning(f"Error getting task start time: {e}")
        return None
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def get_login_data_database(copy_from_env):
    """
    Copy Login Data database from container to host.
    
    Returns:
        Tuple of (local_db_path: str or None, error_message: str)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db', mode='wb')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/login_data_export.db",
            "/home/ga/.config/google-chrome-cdp/Default/Login Data",
            "/home/ga/.config/google-chrome/Default/Login Data",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Login Data from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file has content
                if Path(temp_file.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied Login Data from: {container_path}")
                    return temp_file.name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none worked
        os.unlink(temp_file.name)
        return None, "Login Data database could not be copied from any known location"
        
    except Exception as e:
        if temp_file and os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
        return None, f"Error accessing Login Data: {str(e)}"


def verify_password_entry(db_path, expected_url, expected_username, min_timestamp):
    """
    Verify that the password entry exists in the Login Data database.
    
    Args:
        db_path: Path to local copy of Login Data SQLite database
        expected_url: Expected site URL
        expected_username: Expected username
        min_timestamp: Minimum creation timestamp (Unix seconds)
        
    Returns:
        Dict with verification result
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    try:
        # Connect to SQLite database
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check database structure
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logins';")
        if cursor.fetchone() is None:
            conn.close()
            return {
                "passed": False,
                "score": 0,
                "feedback": "Login Data database does not contain 'logins' table"
            }
        
        # Query for matching entries
        # Chrome stores passwords with origin_url and signon_realm
        query = """
        SELECT origin_url, signon_realm, username_value, password_value, 
               date_created, date_last_used, times_used
        FROM logins
        WHERE (origin_url LIKE ? OR signon_realm LIKE ?)
        ORDER BY date_created DESC
        """
        
        url_pattern = f"%example-testsite.com%"
        cursor.execute(query, (url_pattern, url_pattern))
        results = cursor.fetchall()
        
        logger.info(f"Found {len(results)} entries matching example-testsite.com")
        
        if not results:
            conn.close()
            return {
                "passed": False,
                "score": 0,
                "feedback": "✗ No password entry found for example-testsite.com\n"
                           "Expected: Site URL containing 'example-testsite.com'\n"
                           "Please add the password entry via chrome://settings/passwords"
            }
        
        # Take the most recent entry (should be the one we just added)
        entry = results[0]
        origin_url, signon_realm, username_value, password_value, date_created, date_last_used, times_used = entry
        
        logger.info(f"Most recent entry:")
        logger.info(f"  origin_url: {origin_url}")
        logger.info(f"  signon_realm: {signon_realm}")
        logger.info(f"  username_value: {username_value}")
        logger.info(f"  password_value length: {len(password_value) if password_value else 0}")
        logger.info(f"  date_created: {date_created}")
        
        # Chrome stores timestamps in WebKit/Chrome format (microseconds since 1601-01-01)
        # Convert to Unix timestamp (seconds since 1970-01-01)
        # Chrome timestamp = (Unix timestamp * 1000000) + 11644473600000000
        if date_created:
            # Convert Chrome timestamp to Unix timestamp
            unix_timestamp = (date_created - 11644473600000000) / 1000000
            entry_datetime = datetime.fromtimestamp(unix_timestamp)
            logger.info(f"  Entry created at: {entry_datetime}")
        else:
            unix_timestamp = 0
        
        # Criterion 1: URL matches
        url_matches = expected_url.lower() in origin_url.lower() or expected_url.lower() in signon_realm.lower()
        if url_matches:
            feedback_parts.append(f"✓ Site URL correct: {origin_url}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Site URL mismatch: found '{origin_url}', expected '{expected_url}'")
        
        # Criterion 2: Username matches
        username_matches = username_value == expected_username
        if username_matches:
            feedback_parts.append(f"✓ Username correct: {username_value}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Username mismatch: found '{username_value}', expected '{expected_username}'")
        
        # Criterion 3: Password is present (encrypted, so just check non-empty)
        password_present = password_value is not None and len(password_value) > 0
        if password_present:
            feedback_parts.append(f"✓ Password saved: {len(password_value)} bytes (encrypted)")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Password field is empty or missing")
        
        # Criterion 4: Entry was created during task execution
        # Be lenient with timestamp check since Chrome timestamps can be tricky
        recent_creation = unix_timestamp >= min_timestamp or min_timestamp == 0
        if recent_creation:
            if min_timestamp > 0:
                feedback_parts.append(f"✓ Entry created during task execution")
            else:
                feedback_parts.append(f"⚠ Entry timestamp check skipped (could not verify task start time)")
            criteria_met += 1
        else:
            task_start_dt = datetime.fromtimestamp(min_timestamp)
            feedback_parts.append(f"✗ Entry appears to be older than task start time (created: {entry_datetime}, task started: {task_start_dt})")
        
        conn.close()
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if passed:
            feedback += f"\n\n✅ Password entry successfully added to Chrome password manager!"
        else:
            feedback += f"\n\n❌ Password entry is incomplete or incorrect."
            feedback += f"\nPlease ensure you:"
            feedback += f"\n  1. Navigated to chrome://settings/passwords"
            feedback += f"\n  2. Clicked 'Add' button"
            feedback += f"\n  3. Entered Site: https://example-testsite.com"
            feedback += f"\n  4. Entered Username: testuser@example.com"
            feedback += f"\n  5. Entered Password: SecureP@ssw0rd!123"
            feedback += f"\n  6. Clicked 'Save' button"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "url_matches": url_matches,
                "username_matches": username_matches,
                "password_present": password_present,
                "recent_creation": recent_creation,
                "criteria_met": criteria_met
            }
        }
        
    except sqlite3.Error as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"SQLite error while querying Login Data: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Error verifying password entry: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error verifying password entry: {str(e)}"
        }
