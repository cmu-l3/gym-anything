#!/usr/bin/env python3
"""
Verifier for Chrome Cookie Selective Deletion Task (cookie_selective_delete@1)
Task: Selectively delete tracking cookies while preserving functional cookies

Verification Strategy:
- Copy Chrome Cookies SQLite database from container
- Query cookies table for httpbin.org domain
- Verify tracking_id and analytics_token are NOT present
- Verify session_id and user_pref ARE present with correct values
- Ensure no collateral damage to other cookies
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
    Main verification function for cookie_selective_delete@1 task.
    
    Verifies that:
    1. tracking_id cookie was deleted
    2. analytics_token cookie was deleted
    3. session_id cookie is preserved with correct value
    4. user_pref cookie is preserved with correct value
    5. Only 2 cookies remain for httpbin.org (clean execution)
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Copy cookies database from container
        cookies_db_path, error_msg = copy_cookies_database(copy_from_env)
        
        if cookies_db_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access cookies database: {error_msg}"
            }
        
        # Parse cookies for httpbin.org domain
        cookies = parse_cookies_for_domain(cookies_db_path, "httpbin.org")
        
        # Perform verification
        result = verify_selective_cookie_deletion(cookies)
        
        # Cleanup
        cleanup_temp_files(cookies_db_path)
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


def copy_cookies_database(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Copy Chrome Cookies database from container to host for analysis.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_path: str or None, error_message: str)
    """
    try:
        # Create temporary file for cookies database
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/cookies_final.db",
            "/home/ga/.config/google-chrome-cdp/Default/Cookies",
            "/home/ga/.config/google-chrome/Default/Cookies"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Cookies database from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    logger.info(f"✓ Successfully copied Cookies database from: {container_path}")
                    return temp_path, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, all attempts failed
        if os.path.exists(temp_path):
            os.unlink(temp_path)
        return None, "Could not copy Cookies database from any known location"
        
    except Exception as e:
        logger.error(f"Error copying cookies database: {e}")
        return None, f"Error copying cookies database: {str(e)}"


def parse_cookies_for_domain(cookies_db_path: str, domain: str) -> List[Dict[str, Any]]:
    """
    Extract cookies for a specific domain from Chrome's Cookies SQLite database.
    
    Args:
        cookies_db_path: Path to Cookies database file
        domain: Domain to filter cookies for
        
    Returns:
        List of cookie dictionaries with name, value, and other attributes
    """
    try:
        # Connect to SQLite database
        conn = sqlite3.connect(cookies_db_path)
        cursor = conn.cursor()
        
        # Query cookies table for the domain
        # Chrome stores cookies with host_key like ".httpbin.org" or "httpbin.org"
        query = """
            SELECT name, value, host_key, path, expires_utc, is_secure, is_httponly, 
                   creation_utc, last_access_utc
            FROM cookies 
            WHERE host_key LIKE ?
            ORDER BY name
        """
        
        cursor.execute(query, (f'%{domain}%',))
        results = cursor.fetchall()
        conn.close()
        
        cookies = []
        for row in results:
            cookie = {
                'name': row[0],
                'value': row[1],
                'domain': row[2],
                'path': row[3],
                'expires': row[4],
                'secure': bool(row[5]),
                'httponly': bool(row[6]),
                'created': row[7],
                'last_access': row[8]
            }
            cookies.append(cookie)
            logger.info(f"Found cookie: {cookie['name']}={cookie['value']} (domain: {cookie['domain']})")
        
        logger.info(f"Total cookies found for {domain}: {len(cookies)}")
        return cookies
        
    except sqlite3.Error as e:
        logger.error(f"SQLite error while parsing cookies: {e}")
        return []
    except Exception as e:
        logger.error(f"Error parsing cookies: {e}")
        return []


def verify_selective_cookie_deletion(cookies: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Verify that specific cookies were deleted and others preserved.
    
    Checks 5 criteria:
    1. tracking_id cookie is deleted (NOT present)
    2. analytics_token cookie is deleted (NOT present)
    3. session_id cookie is preserved with value 'abc123'
    4. user_pref cookie is preserved with value 'dark_mode'
    5. Exactly 2 cookies remain (clean execution, no extras)
    
    Args:
        cookies: List of cookie dictionaries
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Create a lookup map by cookie name
    cookie_map = {cookie['name']: cookie for cookie in cookies}
    cookie_names = set(cookie_map.keys())
    
    # Criterion 1: tracking_id should be deleted (NOT present)
    tracking_deleted = 'tracking_id' not in cookie_names
    logger.info(f"Criterion 1 - tracking_id deleted: {tracking_deleted}")
    
    # Criterion 2: analytics_token should be deleted (NOT present)
    analytics_deleted = 'analytics_token' not in cookie_names
    logger.info(f"Criterion 2 - analytics_token deleted: {analytics_deleted}")
    
    # Criterion 3: session_id should be preserved with correct value
    session_preserved = False
    session_value_correct = False
    if 'session_id' in cookie_names:
        session_preserved = True
        session_cookie = cookie_map['session_id']
        session_value_correct = session_cookie['value'] == 'abc123'
    session_ok = session_preserved and session_value_correct
    logger.info(f"Criterion 3 - session_id preserved with correct value: {session_ok} (present: {session_preserved}, value: {session_value_correct})")
    
    # Criterion 4: user_pref should be preserved with correct value
    pref_preserved = False
    pref_value_correct = False
    if 'user_pref' in cookie_names:
        pref_preserved = True
        pref_cookie = cookie_map['user_pref']
        pref_value_correct = pref_cookie['value'] == 'dark_mode'
    pref_ok = pref_preserved and pref_value_correct
    logger.info(f"Criterion 4 - user_pref preserved with correct value: {pref_ok} (present: {pref_preserved}, value: {pref_value_correct})")
    
    # Criterion 5: Exactly 2 cookies should remain
    clean_execution = len(cookies) == 2
    logger.info(f"Criterion 5 - clean execution (exactly 2 cookies): {clean_execution} (found: {len(cookies)})")
    
    # Calculate score
    criteria_results = [
        tracking_deleted,
        analytics_deleted,
        session_ok,
        pref_ok,
        clean_execution
    ]
    criteria_met = sum(criteria_results)
    score = int((criteria_met / 5.0) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (80%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Cookie Selective Deletion Verification: {criteria_met}/5 criteria met\n")
    
    # Criterion 1 feedback
    if tracking_deleted:
        feedback_parts.append("✓ Criterion 1: tracking_id cookie successfully deleted")
    else:
        feedback_parts.append("✗ Criterion 1: tracking_id cookie still present (should be deleted)")
    
    # Criterion 2 feedback
    if analytics_deleted:
        feedback_parts.append("✓ Criterion 2: analytics_token cookie successfully deleted")
    else:
        feedback_parts.append("✗ Criterion 2: analytics_token cookie still present (should be deleted)")
    
    # Criterion 3 feedback
    if session_ok:
        feedback_parts.append("✓ Criterion 3: session_id cookie preserved with correct value (abc123)")
    elif session_preserved and not session_value_correct:
        actual_value = cookie_map['session_id']['value']
        feedback_parts.append(f"✗ Criterion 3: session_id preserved but value incorrect (got: {actual_value}, expected: abc123)")
    else:
        feedback_parts.append("✗ Criterion 3: session_id cookie deleted (should be preserved)")
    
    # Criterion 4 feedback
    if pref_ok:
        feedback_parts.append("✓ Criterion 4: user_pref cookie preserved with correct value (dark_mode)")
    elif pref_preserved and not pref_value_correct:
        actual_value = cookie_map['user_pref']['value']
        feedback_parts.append(f"✗ Criterion 4: user_pref preserved but value incorrect (got: {actual_value}, expected: dark_mode)")
    else:
        feedback_parts.append("✗ Criterion 4: user_pref cookie deleted (should be preserved)")
    
    # Criterion 5 feedback
    if clean_execution:
        feedback_parts.append("✓ Criterion 5: Clean execution - exactly 2 cookies remain")
    else:
        feedback_parts.append(f"✗ Criterion 5: Incorrect cookie count - {len(cookies)} cookies found (expected: 2)")
        if len(cookies) > 2:
            extra_cookies = [name for name in cookie_names if name not in ['session_id', 'user_pref']]
            feedback_parts.append(f"  Extra cookies present: {', '.join(extra_cookies)}")
        elif len(cookies) < 2:
            feedback_parts.append(f"  Too few cookies - may have deleted too many")
    
    # Summary
    feedback_parts.append(f"\n{'='*50}")
    feedback_parts.append(f"Final Score: {score}% ({criteria_met}/5 criteria)")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if len(cookies) > 0:
        feedback_parts.append(f"\nRemaining cookies for httpbin.org:")
        for cookie in cookies:
            feedback_parts.append(f"  - {cookie['name']}={cookie['value']}")
    else:
        feedback_parts.append(f"\n⚠ No cookies found for httpbin.org (all deleted?)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "tracking_deleted": tracking_deleted,
            "analytics_deleted": analytics_deleted,
            "session_preserved": session_ok,
            "pref_preserved": pref_ok,
            "clean_execution": clean_execution,
            "cookie_count": len(cookies),
            "remaining_cookies": list(cookie_names)
        }
    }


def cleanup_temp_files(temp_db_path: str):
    """Clean up temporary database file."""
    try:
        if temp_db_path and os.path.exists(temp_db_path):
            os.unlink(temp_db_path)
            logger.info("Cleaned up temporary database file")
    except Exception as e:
        logger.warning(f"Could not cleanup temp file: {e}")
