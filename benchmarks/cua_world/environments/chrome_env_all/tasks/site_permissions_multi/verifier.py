#!/usr/bin/env python3
"""
Verifier for Chrome Site Permissions Configuration Task (site_permissions_multi@1)

Task: Configure site-specific permissions for multiple websites across notification and location categories

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to access profile.content_settings.exceptions
- Check notifications exceptions for example.com (BLOCK) and trusted-site.org (ALLOW)
- Check geolocation exceptions for maps-service.com (ALLOW) and tracker-site.com (BLOCK)
- Validate correct Chrome permission setting codes (1=ALLOW, 2=BLOCK)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        """Fallback preferences parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup"""
        pass


# Chrome permission setting codes
PERMISSION_DEFAULT = 0  # Ask (default)
PERMISSION_ALLOW = 1    # Allow
PERMISSION_BLOCK = 2    # Block


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_permissions_multi@1.
    
    Verifies that site permissions were correctly configured:
    - Notifications: example.com blocked, trusted-site.org allowed
    - Location: maps-service.com allowed, tracker-site.com blocked
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Extract preferences data
        prefs_data, error_msg = get_preferences_data(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Chrome preferences: {error_msg}"
            }
        
        # Verify site permissions configuration
        result = verify_site_permissions(prefs_data)
        
        # Clean up temporary files
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


def get_preferences_data(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    try:
        # Create temporary file for preferences
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        preferences_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded preferences from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Validate basic structure
        if 'profile' not in prefs_data:
            return None, "Invalid Preferences structure - missing 'profile' key"
        
        return prefs_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error retrieving preferences: {e}"
    finally:
        # Clean up temporary file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except Exception:
                pass


def check_permission(permission_dict: Dict, domain: str, expected_setting: int) -> Tuple[bool, str]:
    """
    Check if a domain has the expected permission setting.
    
    Chrome stores permissions with patterns like:
    - 'https://domain.com:443,*'
    - '[*.]domain.com:443'
    - 'https://[*.]domain.com:443,*'
    
    Args:
        permission_dict: Dictionary of permission patterns and settings
        domain: Domain name to check (e.g., 'example.com')
        expected_setting: Expected permission value (1=ALLOW, 2=BLOCK)
        
    Returns:
        Tuple of (found: bool, details: str)
    """
    if not permission_dict:
        return False, "Permission dictionary is empty"
    
    # Normalize domain for comparison
    domain_normalized = domain.lower().replace('https://', '').replace('http://', '').rstrip('/')
    
    found_patterns = []
    
    for pattern, settings in permission_dict.items():
        pattern_lower = pattern.lower()
        
        # Check if domain appears in pattern
        if domain_normalized in pattern_lower:
            setting_value = settings.get('setting', -1)
            found_patterns.append(f"{pattern} (setting={setting_value})")
            
            # Check if setting matches expected value
            if setting_value == expected_setting:
                return True, f"Found correct setting for {domain} in pattern: {pattern}"
    
    if found_patterns:
        return False, f"Found {domain} but with wrong setting: {found_patterns}"
    else:
        return False, f"Domain {domain} not found in permissions"


def verify_site_permissions(prefs_data: Dict) -> Dict[str, Any]:
    """
    Verify that site permissions were correctly configured.
    
    Checks 4 criteria (need all 4 for 100%, 3 for pass):
    1. example.com blocked for notifications (setting=2)
    2. trusted-site.org allowed for notifications (setting=1)
    3. maps-service.com allowed for location (setting=1)
    4. tracker-site.com blocked for location (setting=2)
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    try:
        # Navigate to content_settings.exceptions
        content_settings = prefs_data.get('profile', {}).get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        
        # Get permission dictionaries
        notifications = exceptions.get('notifications', {})
        geolocation = exceptions.get('geolocation', {})
        
        logger.info(f"Found {len(notifications)} notification exceptions")
        logger.info(f"Found {len(geolocation)} geolocation exceptions")
        
        # Check each required permission
        checks = {
            'notifications_blocked': check_permission(notifications, 'example.com', PERMISSION_BLOCK),
            'notifications_allowed': check_permission(notifications, 'trusted-site.org', PERMISSION_ALLOW),
            'location_allowed': check_permission(geolocation, 'maps-service.com', PERMISSION_ALLOW),
            'location_blocked': check_permission(geolocation, 'tracker-site.com', PERMISSION_BLOCK)
        }
        
        # Log detailed results
        for check_name, (passed, details) in checks.items():
            status = "✓" if passed else "✗"
            logger.info(f"{status} {check_name}: {details}")
        
        # Calculate score
        passed_checks = sum(1 for passed, _ in checks.values() if passed)
        score = int((passed_checks / 4) * 100)
        passed_overall = score >= 75  # Need 3/4 to pass
        
        # Generate detailed feedback
        feedback_parts = []
        feedback_parts.append(f"Site Permissions Verification: {passed_checks}/4 criteria met")
        feedback_parts.append("")
        
        # Notifications section
        feedback_parts.append("Notifications Permissions:")
        notif_blocked_ok, notif_blocked_msg = checks['notifications_blocked']
        notif_allowed_ok, notif_allowed_msg = checks['notifications_allowed']
        
        feedback_parts.append(f"  {'✓' if notif_blocked_ok else '✗'} example.com blocked: {notif_blocked_msg}")
        feedback_parts.append(f"  {'✓' if notif_allowed_ok else '✗'} trusted-site.org allowed: {notif_allowed_msg}")
        
        # Location section
        feedback_parts.append("")
        feedback_parts.append("Location Permissions:")
        loc_allowed_ok, loc_allowed_msg = checks['location_allowed']
        loc_blocked_ok, loc_blocked_msg = checks['location_blocked']
        
        feedback_parts.append(f"  {'✓' if loc_allowed_ok else '✗'} maps-service.com allowed: {loc_allowed_msg}")
        feedback_parts.append(f"  {'✓' if loc_blocked_ok else '✗'} tracker-site.com blocked: {loc_blocked_msg}")
        
        # Overall result
        feedback_parts.append("")
        feedback_parts.append(f"Score: {score}/100")
        
        if passed_overall:
            if score == 100:
                feedback_parts.append("✅ Perfect! All site permissions configured correctly!")
            else:
                feedback_parts.append(f"✅ Task passed with {passed_checks}/4 criteria met")
        else:
            feedback_parts.append(f"❌ Task incomplete - only {passed_checks}/4 permissions configured correctly")
            feedback_parts.append("Navigate to chrome://settings/content to configure site permissions")
        
        feedback = "\n".join(feedback_parts)
        
        return {
            "passed": passed_overall,
            "score": score,
            "feedback": feedback,
            "details": {
                "checks_passed": passed_checks,
                "notifications_blocked": notif_blocked_ok,
                "notifications_allowed": notif_allowed_ok,
                "location_allowed": loc_allowed_ok,
                "location_blocked": loc_blocked_ok
            }
        }
        
    except KeyError as e:
        logger.error(f"Preferences structure missing expected key: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid Preferences structure - missing key: {e}. Permissions may not have been configured.",
            "details": {"error": str(e)}
        }
    except Exception as e:
        logger.error(f"Error verifying permissions: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "details": {"error": str(e)}
        }
