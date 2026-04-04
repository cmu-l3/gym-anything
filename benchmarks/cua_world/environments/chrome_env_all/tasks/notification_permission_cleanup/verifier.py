#!/usr/bin/env python3
"""
Verifier for Chrome Site Notification Permission Revocation Task (notification_permission_cleanup@1)
Task: Revoke notification permissions from unwanted websites while preserving wanted ones

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.notifications
- Verify target domains (newsdaily.com, celebritygossip.net, dealsalert.shop) are blocked or absent
- Verify control domain (work-calendar.company.com) retains ALLOW permission
- Score based on criteria met (3 revoked + 1 preserved = 4 criteria)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple

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

# Chrome content setting values
CONTENT_SETTING_DEFAULT = 0
CONTENT_SETTING_ALLOW = 1
CONTENT_SETTING_BLOCK = 2


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for notification_permission_cleanup@1.
    
    Verifies that notification permissions were correctly revoked for target domains
    while preserving permissions for control domains.
    
    Args:
        traj: Trajectory data (unused for this verification)
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
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Get preferences data from container
        prefs_data = get_preferences_data(copy_from_env)
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve Chrome Preferences file"
            }

        # Perform verification
        verification_result = verify_notification_permissions(prefs_data)
        
        # Clean up temporary files
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


def get_preferences_data(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Parsed Preferences JSON data, or None on failure
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return prefs_data
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"Error getting Preferences data: {e}")
        return None
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def check_domain_permission_state(notifications: Dict[str, Any], domain: str) -> Tuple[str, int]:
    """
    Check the permission state for a given domain.
    
    Args:
        notifications: The notifications section from Chrome Preferences
        domain: Base domain to check (e.g., "newsdaily.com")
        
    Returns:
        Tuple of (state: str, setting: int)
        state can be: "allowed", "blocked", "absent"
        setting is the raw Chrome setting value
    """
    # Generate possible domain patterns that Chrome might use
    domain_patterns = [
        f"https://{domain}:443,*",
        f"http://{domain}:80,*",
        f"https://www.{domain}:443,*",
        f"http://www.{domain}:80,*",
        f"[*.]%s,*" % domain
    ]
    
    for pattern in domain_patterns:
        if pattern in notifications:
            setting = notifications[pattern].get('setting')
            
            if setting == CONTENT_SETTING_ALLOW:
                return "allowed", setting
            elif setting == CONTENT_SETTING_BLOCK:
                return "blocked", setting
            else:
                return "other", setting
    
    # Not found in any pattern
    return "absent", -1


def verify_notification_permissions(prefs_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify notification permission states for all target and control domains.
    
    Criteria:
    1. newsdaily.com is blocked or absent
    2. celebritygossip.net is blocked or absent
    3. dealsalert.shop is blocked or absent
    4. work-calendar.company.com retains ALLOW permission
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        
    Returns:
        Dict with passed, score, feedback, and detailed results
    """
    # Define target domains (should be revoked)
    target_domains = [
        "newsdaily.com",
        "celebritygossip.net",
        "dealsalert.shop"
    ]
    
    # Define control domains (should be preserved)
    preserve_domains = [
        "work-calendar.company.com"
    ]
    
    # Navigate to notifications section
    try:
        notifications = prefs_data.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('notifications', {})
    except Exception as e:
        logger.error(f"Failed to navigate to notifications section: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Chrome Preferences file does not contain notification settings structure"
        }
    
    if not notifications:
        logger.warning("Notifications section is empty or missing")
    
    logger.info(f"Found {len(notifications)} notification permission entries")
    logger.info(f"Notification entries: {list(notifications.keys())}")
    
    # Check each target domain (should be blocked or absent)
    target_results = {}
    for domain in target_domains:
        state, setting = check_domain_permission_state(notifications, domain)
        is_revoked = state in ["blocked", "absent"]
        target_results[domain] = {
            "state": state,
            "setting": setting,
            "revoked": is_revoked
        }
        logger.info(f"  {domain}: {state} (setting={setting}) - {'✓ REVOKED' if is_revoked else '✗ STILL ALLOWED'}")
    
    # Check each control domain (should still be allowed)
    preserve_results = {}
    for domain in preserve_domains:
        state, setting = check_domain_permission_state(notifications, domain)
        is_preserved = (state == "allowed")
        preserve_results[domain] = {
            "state": state,
            "setting": setting,
            "preserved": is_preserved
        }
        logger.info(f"  {domain}: {state} (setting={setting}) - {'✓ PRESERVED' if is_preserved else '✗ NOT PRESERVED'}")
    
    # Calculate criteria met
    criteria_results = []
    
    # Criterion 1-3: Target domains revoked
    for domain in target_domains:
        criteria_results.append(target_results[domain]["revoked"])
    
    # Criterion 4: Control domain preserved
    for domain in preserve_domains:
        criteria_results.append(preserve_results[domain]["preserved"])
    
    criteria_met = sum(criteria_results)
    total_criteria = len(criteria_results)
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria (75%)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Notification Permission Verification: {criteria_met}/{total_criteria} criteria met")
    feedback_parts.append("")
    feedback_parts.append("Target domains (should be revoked):")
    
    for domain in target_domains:
        result = target_results[domain]
        status = "✓" if result["revoked"] else "✗"
        feedback_parts.append(f"  {status} {domain}: {result['state']}")
    
    feedback_parts.append("")
    feedback_parts.append("Control domains (should be preserved):")
    
    for domain in preserve_domains:
        result = preserve_results[domain]
        status = "✓" if result["preserved"] else "✗"
        feedback_parts.append(f"  {status} {domain}: {result['state']}")
    
    feedback_parts.append("")
    feedback_parts.append(f"Score: {score}% ({criteria_met}/{total_criteria})")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ Perfect! All notification permissions correctly managed.")
        else:
            feedback_parts.append("✅ Task completed with minor issues.")
    else:
        feedback_parts.append("❌ Task incomplete - notification permissions not properly revoked.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "target_results": target_results,
            "preserve_results": preserve_results,
            "notifications_count": len(notifications)
        }
    }
