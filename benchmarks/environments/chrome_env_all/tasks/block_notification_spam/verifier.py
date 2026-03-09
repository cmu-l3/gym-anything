#!/usr/bin/env python3
"""
Verifier for Chrome Block Notification Spam Task (block_notification_spam@1)
Task: Block notification permissions for news-spam-example.com

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to access profile.content_settings.exceptions.notifications
- Check if spam domain (news-spam-example.com) is blocked or removed
- Validate that permission is not ALLOW (1)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


# Permission values used by Chrome
PERMISSION_DEFAULT = 0  # Ask (default)
PERMISSION_ALLOW = 1    # Allow
PERMISSION_BLOCK = 2    # Block
PERMISSION_ASK = 3      # Explicitly ask

# Spam domain we're checking (with possible variants)
SPAM_DOMAIN_VARIANTS = [
    "https://news-spam-example.com:443,*",
    "http://news-spam-example.com:80,*",
    "https://news-spam-example.com,*",
    "http://news-spam-example.com,*",
]


def verify_task(traj, env_info, task_info):
    """
    Main verification function for block_notification_spam@1.
    
    Verifies that notification permission for news-spam-example.com has been
    blocked or removed from the allowed list.
    
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
        # Extract notification permissions from Chrome Preferences
        permissions, error_msg = extract_notification_permissions(copy_from_env)
        
        if permissions is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract notification permissions: {error_msg}"
            }
        
        # Verify the spam domain is blocked or removed
        result = verify_spam_domain_blocked(permissions)
        
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


def extract_notification_permissions(copy_from_env):
    """
    Extract notification permissions from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (permissions: dict or None, error_message: str)
    """
    temp_file = None
    try:
        # Create temporary file for Preferences
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple possible locations for Preferences file
        preferences_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 10:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
                else:
                    logger.debug(f"File empty or missing from {container_path}")
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Navigate nested JSON structure to find notification permissions
        notifications = prefs_data.get('profile', {}).get(
            'content_settings', {}
        ).get('exceptions', {}).get('notifications', {})
        
        if not isinstance(notifications, dict):
            return None, "Notification permissions section not found in Preferences"
        
        logger.info(f"Found {len(notifications)} notification permission entries")
        for domain, perm in notifications.items():
            setting = perm.get('setting', 0)
            setting_name = {0: 'ASK', 1: 'ALLOW', 2: 'BLOCK'}.get(setting, f'UNKNOWN({setting})')
            logger.info(f"  {domain}: {setting_name}")
        
        return notifications, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting notification permissions: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_spam_domain_blocked(permissions):
    """
    Verify that the spam domain notification permission is blocked or removed.
    
    Args:
        permissions: Dictionary of notification permissions from Chrome Preferences
        
    Returns:
        Dict with passed, score, and feedback
    """
    # Check if spam domain exists in permissions
    spam_domain_found = None
    spam_domain_key = None
    
    for variant in SPAM_DOMAIN_VARIANTS:
        if variant in permissions:
            spam_domain_found = permissions[variant]
            spam_domain_key = variant
            break
    
    # Case 1: Domain not found (removed from list) - SUCCESS
    if spam_domain_found is None:
        logger.info("✓ Spam domain not found in notification permissions (removed)")
        return {
            "passed": True,
            "score": 100,
            "feedback": "✓ Notification permission for news-spam-example.com was successfully removed from the allowed list. No more spam notifications!",
            "details": {
                "action": "removed",
                "domain": "news-spam-example.com",
                "total_permissions": len(permissions)
            }
        }
    
    # Case 2: Domain found, check its permission setting
    permission_setting = spam_domain_found.get('setting', PERMISSION_DEFAULT)
    logger.info(f"Spam domain found with setting: {permission_setting}")
    
    # Case 2a: Explicitly blocked - SUCCESS
    if permission_setting == PERMISSION_BLOCK:
        logger.info("✓ Spam domain explicitly blocked")
        return {
            "passed": True,
            "score": 100,
            "feedback": "✓ Notification permission for news-spam-example.com was successfully blocked. Spam notifications are now prevented!",
            "details": {
                "action": "blocked",
                "domain": spam_domain_key,
                "setting": "BLOCK",
                "total_permissions": len(permissions)
            }
        }
    
    # Case 2b: Still allowed - FAILURE
    if permission_setting == PERMISSION_ALLOW:
        logger.info("✗ Spam domain still has ALLOW permission")
        return {
            "passed": False,
            "score": 0,
            "feedback": "✗ The domain news-spam-example.com still has ALLOW permission for notifications. You need to navigate to Chrome Settings > Privacy and security > Site Settings > Notifications, find the domain, and change its permission to Block or remove it.",
            "details": {
                "action": "unchanged",
                "domain": spam_domain_key,
                "setting": "ALLOW",
                "total_permissions": len(permissions)
            }
        }
    
    # Case 2c: Set to ASK/DEFAULT - PARTIAL SUCCESS
    if permission_setting in [PERMISSION_DEFAULT, PERMISSION_ASK]:
        logger.info("⚠ Spam domain set to ASK/DEFAULT (partial success)")
        return {
            "passed": True,
            "score": 75,
            "feedback": "⚠ The domain news-spam-example.com was changed to ASK permission. This is better than ALLOW, but setting it to BLOCK would be more definitive in preventing spam notifications.",
            "details": {
                "action": "changed_to_ask",
                "domain": spam_domain_key,
                "setting": "ASK",
                "total_permissions": len(permissions)
            }
        }
    
    # Case 2d: Unknown setting - UNCLEAR
    logger.warning(f"Unknown permission setting: {permission_setting}")
    return {
        "passed": False,
        "score": 25,
        "feedback": f"⚠ The domain has an unexpected permission setting ({permission_setting}). Cannot determine if notifications are blocked.",
        "details": {
            "action": "unknown",
            "domain": spam_domain_key,
            "setting": f"UNKNOWN({permission_setting})",
            "total_permissions": len(permissions)
        }
    }
