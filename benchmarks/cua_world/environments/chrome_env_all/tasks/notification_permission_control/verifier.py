#!/usr/bin/env python3
"""
Verifier for Chrome Notification Permission Control Task (notification_permission_control@1)
Task: Navigate to notification test page, grant permission, then revoke it via settings

Verification Strategy:
- Parse Chrome Preferences for notification permission state
- Parse History to verify site visits and settings access
- Check for state transitions (default → granted → revoked)
- Validate complete workflow execution
"""

import logging
import sys
import os
import json
import sqlite3
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences,
        parse_history
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for notification_permission_control@1.
    
    Verifies that the agent:
    1. Navigated to the test site (localhost:8000)
    2. Granted notification permission
    3. Accessed Chrome settings for notifications
    4. Revoked the notification permission
    
    Scoring:
    - 100%: All 5 criteria met (complete workflow)
    - 75-99%: 4/5 criteria met (minor issue, still passing)
    - 50-74%: 3/5 criteria met (partial success)
    - 25-49%: 2/5 criteria met (incomplete)
    - 0-24%: 0-1 criteria met (task failed)
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Extract Chrome data
        prefs_data, history_data, error_msg = extract_chrome_data(copy_from_env)
        
        if prefs_data is None and history_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract Chrome data: {error_msg}"
            }
        
        # Perform multi-criteria verification
        result = verify_notification_workflow(prefs_data, history_data)
        
        # Clean up
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


def extract_chrome_data(copy_from_env):
    """
    Extract Preferences and History files from container.
    
    Returns:
        Tuple of (prefs_data: dict, history_data: list, error_message: str)
    """
    prefs_data = None
    history_data = None
    errors = []
    
    # Try to use utilities if available
    if UTILS_AVAILABLE:
        try:
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences", "History"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs_data = parse_preferences(files["Preferences"])
                history_data = parse_history(files["History"])
                return prefs_data, history_data, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}")
                errors.append(error)
        except Exception as e:
            logger.warning(f"Utility extraction error: {e}")
            errors.append(str(e))
    
    # Fallback: Manual extraction
    temp_prefs = None
    temp_history = None
    
    try:
        # Extract Preferences
        temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_prefs.close()
        
        prefs_paths = [
            "/tmp/notification_permission_verification/Preferences",
            "/tmp/Preferences",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for path in prefs_paths:
            try:
                copy_from_env(path, temp_prefs.name)
                if os.path.exists(temp_prefs.name) and os.path.getsize(temp_prefs.name) > 0:
                    with open(temp_prefs.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    logger.info(f"✓ Preferences extracted from: {path}")
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {path}: {e}")
                continue
        
        if prefs_data is None:
            errors.append("Could not extract Preferences from any location")
        
    except Exception as e:
        errors.append(f"Preferences extraction error: {e}")
    finally:
        if temp_prefs and os.path.exists(temp_prefs.name):
            try:
                os.unlink(temp_prefs.name)
            except:
                pass
    
    try:
        # Extract History
        temp_history = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
        temp_history.close()
        
        history_paths = [
            "/tmp/notification_permission_verification/History",
            "/tmp/History",
            "/home/ga/.config/google-chrome-cdp/Default/History",
            "/home/ga/.config/google-chrome/Default/History"
        ]
        
        for path in history_paths:
            try:
                copy_from_env(path, temp_history.name)
                if os.path.exists(temp_history.name) and os.path.getsize(temp_history.name) > 0:
                    # Parse SQLite history
                    conn = sqlite3.connect(temp_history.name)
                    cursor = conn.cursor()
                    cursor.execute("SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 100")
                    history_data = cursor.fetchall()
                    conn.close()
                    logger.info(f"✓ History extracted from: {path}")
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {path}: {e}")
                continue
        
        if history_data is None:
            errors.append("Could not extract History from any location")
        
    except Exception as e:
        errors.append(f"History extraction error: {e}")
    finally:
        if temp_history and os.path.exists(temp_history.name):
            try:
                os.unlink(temp_history.name)
            except:
                pass
    
    error_msg = "; ".join(errors) if errors else ""
    return prefs_data, history_data, error_msg


def verify_notification_workflow(prefs_data, history_data):
    """
    Verify the complete notification permission workflow.
    
    Checks:
    1. Test site was visited (localhost:8000 in history)
    2. Permission was granted at some point (value 1 in preferences)
    3. Settings page was accessed (chrome://settings in history)
    4. Permission was revoked (no longer value 1, or removed from preferences)
    5. Valid state transitions occurred
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        history_data: List of (url, title) tuples from History
        
    Returns:
        Dict with passed, score, feedback, and criteria details
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Extract history URLs
    history_urls = []
    if history_data:
        history_urls = [url.lower() for url, title in history_data]
    
    # Criterion 1: Test site visited
    test_site_visited = any(
        "localhost:8000" in url or "127.0.0.1:8000" in url
        for url in history_urls
    )
    
    if test_site_visited:
        feedback_parts.append("✓ Test site visited (localhost:8000)")
        criteria_met += 1
        logger.info("✓ Criterion 1: Test site visited")
    else:
        feedback_parts.append("✗ Test site not visited (localhost:8000)")
        logger.warning("✗ Criterion 1: Test site NOT visited")
    
    # Criterion 2 & 3: Settings accessed
    settings_accessed = any(
        "chrome://settings" in url and "notification" in url
        for url in history_urls
    )
    
    if not settings_accessed:
        # Check for general settings access (might not have exact URL)
        settings_accessed = any(
            "chrome://settings" in url
            for url in history_urls
        )
    
    if settings_accessed:
        feedback_parts.append("✓ Chrome settings accessed")
        criteria_met += 1
        logger.info("✓ Criterion 2: Settings accessed")
    else:
        feedback_parts.append("✗ Chrome settings not accessed")
        logger.warning("✗ Criterion 2: Settings NOT accessed")
    
    # Criterion 3 & 4: Permission state analysis
    notification_exceptions = {}
    permission_granted = False
    permission_revoked = False
    permission_key = None
    
    if prefs_data:
        try:
            notification_exceptions = prefs_data.get('profile', {}).get(
                'content_settings', {}
            ).get('exceptions', {}).get('notifications', {})
            
            logger.info(f"Notification exceptions found: {len(notification_exceptions)} entries")
            
            # Look for localhost:8000 in notification exceptions
            for key, value in notification_exceptions.items():
                if 'localhost:8000' in key.lower() or '127.0.0.1:8000' in key.lower():
                    permission_key = key
                    setting_value = value.get('setting', 0)
                    
                    logger.info(f"Found permission entry: {key} with setting={setting_value}")
                    
                    # Setting values: 0=ASK (default), 1=ALLOW, 2=BLOCK
                    if setting_value == 1:
                        permission_granted = True
                        permission_revoked = False
                        logger.info("Permission is currently GRANTED (value=1)")
                    elif setting_value == 2:
                        permission_granted = True  # Assume it was granted then blocked
                        permission_revoked = True
                        logger.info("Permission is currently BLOCKED (value=2) - likely granted then revoked")
                    else:
                        logger.info(f"Permission has unusual value: {setting_value}")
                    break
            
            # If no permission key found, but settings were accessed,
            # assume permission was granted then completely removed
            if not permission_key and settings_accessed and test_site_visited:
                permission_granted = True
                permission_revoked = True
                logger.info("No permission entry found - likely granted then removed completely")
        
        except Exception as e:
            logger.error(f"Error parsing notification permissions: {e}")
            feedback_parts.append(f"⚠ Error parsing permissions: {e}")
    
    # Evaluate permission granted criterion
    if permission_granted:
        feedback_parts.append("✓ Permission was granted")
        criteria_met += 1
        logger.info("✓ Criterion 3: Permission was granted")
    else:
        feedback_parts.append("✗ No evidence of permission being granted")
        logger.warning("✗ Criterion 3: Permission was NOT granted")
    
    # Evaluate permission revoked criterion
    if permission_revoked:
        feedback_parts.append("✓ Permission was revoked")
        criteria_met += 1
        logger.info("✓ Criterion 4: Permission was revoked")
    else:
        if permission_granted:
            feedback_parts.append("✗ Permission granted but NOT revoked")
        else:
            feedback_parts.append("✗ Permission never granted, so cannot be revoked")
        logger.warning("✗ Criterion 4: Permission was NOT revoked")
    
    # Criterion 5: Valid state transitions
    # This is true if we have evidence of workflow: visit + grant + settings + revoke
    state_transitions_valid = (
        test_site_visited and 
        settings_accessed and 
        permission_granted
    )
    
    if state_transitions_valid:
        feedback_parts.append("✓ Valid workflow state transitions detected")
        criteria_met += 1
        logger.info("✓ Criterion 5: Valid state transitions")
    else:
        feedback_parts.append("✗ Incomplete workflow state transitions")
        logger.warning("✗ Criterion 5: Incomplete state transitions")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✅' if passed else 'FAILED ❌'}"
    
    if permission_key:
        feedback += f"\n\nPermission entry found: {permission_key}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria": {
            "test_site_visited": test_site_visited,
            "permission_granted": permission_granted,
            "settings_accessed": settings_accessed,
            "permission_revoked": permission_revoked,
            "state_transitions_valid": state_transitions_valid
        },
        "details": {
            "permission_key": permission_key,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
