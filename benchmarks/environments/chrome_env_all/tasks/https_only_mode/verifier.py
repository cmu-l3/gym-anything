#!/usr/bin/env python3
"""
Verifier for Chrome HTTPS-Only Mode Configuration Task (https_only_mode@1)
Task: Enable Chrome's HTTPS-First Mode (Always use secure connections)

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and check multiple possible setting locations
- Verify HTTPS-Only mode is explicitly enabled (value = true)
- Handle different Chrome versions with different preference keys
- Provide detailed feedback on setting status
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
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for https_only_mode@1.
    
    Verifies that Chrome's HTTPS-Only Mode has been enabled by checking
    the Preferences file for the appropriate setting.
    
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
            "feedback": "❌ Copy function not available in environment - cannot verify task"
        }

    try:
        # Extract HTTPS-Only mode setting from Preferences
        https_enabled, setting_location, error_msg = extract_https_only_setting(copy_from_env)
        
        if error_msg:
            # If there was an error extracting the setting
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ {error_msg}"
            }
        
        # Validate the setting
        is_valid, score, feedback = validate_https_only_setting(https_enabled, setting_location)
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "https_only_enabled": https_enabled,
                "setting_location": setting_location
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def extract_https_only_setting(copy_from_env) -> Tuple[Optional[bool], Optional[str], str]:
    """
    Extract HTTPS-Only mode setting from Chrome Preferences file.
    
    Checks multiple possible setting locations:
    - generated.https_only_mode_enabled (Chrome 94+)
    - https_only_mode_enabled (alternative location)
    - generated.https_first_mode_enabled (newer Chrome versions)
    - profile.content_settings.exceptions.insecure_content (content settings approach)
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (https_enabled: bool or None, setting_location: str or None, error_message: str)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use chrome_verification_utils...")
            success, files, error = setup_chrome_verification(
                copy_from_env,
                ["Preferences"],
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs_path = files["Preferences"]
                prefs = parse_preferences(prefs_path)
                cleanup_verification_temp()
                
                if prefs:
                    return check_https_settings_in_prefs(prefs)
                else:
                    logger.warning("Utilities parsed empty preferences, trying fallback")
        
        # Fallback: Manual extraction
        logger.info("Using fallback manual extraction method...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible source locations
        source_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_used = None
        
        for container_path in source_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_used = container_path
                    logger.info(f"✓ Successfully copied and parsed from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            return None, None, "Could not access Preferences file from any known location"
        
        # Check for HTTPS-Only mode settings in the preferences
        return check_https_settings_in_prefs(prefs)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Extraction error: {e}", exc_info=True)
        return None, None, f"Error extracting HTTPS-Only setting: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
        cleanup_verification_temp()


def check_https_settings_in_prefs(prefs: Dict[str, Any]) -> Tuple[Optional[bool], Optional[str], str]:
    """
    Check multiple possible locations for HTTPS-Only mode setting in preferences.
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Tuple of (https_enabled: bool or None, setting_location: str or None, error_message: str)
    """
    # Check 1: generated.https_only_mode_enabled (most common in Chrome 94+)
    if prefs.get('generated', {}).get('https_only_mode_enabled') is True:
        logger.info("✓ Found enabled at: generated.https_only_mode_enabled")
        return True, "generated.https_only_mode_enabled", ""
    
    # Check 2: Direct https_only_mode_enabled
    if prefs.get('https_only_mode_enabled') is True:
        logger.info("✓ Found enabled at: https_only_mode_enabled")
        return True, "https_only_mode_enabled", ""
    
    # Check 3: generated.https_first_mode_enabled (newer Chrome versions)
    if prefs.get('generated', {}).get('https_first_mode_enabled') is True:
        logger.info("✓ Found enabled at: generated.https_first_mode_enabled")
        return True, "generated.https_first_mode_enabled", ""
    
    # Check 4: Content settings for insecure content blocking
    # Path: profile.content_settings.exceptions.insecure_content.*,*.setting
    insecure_content = (prefs.get('profile', {})
                              .get('content_settings', {})
                              .get('exceptions', {})
                              .get('insecure_content', {}))
    
    for key, value in insecure_content.items():
        if isinstance(value, dict):
            setting_value = value.get('setting')
            # Setting value 2 typically means "Block"
            if setting_value == 2:
                logger.info(f"✓ Found insecure content blocked at: content_settings.insecure_content.{key}")
                return True, f"content_settings.insecure_content.{key}.setting=2", ""
    
    # Check if any of the keys exist but are set to False
    if prefs.get('generated', {}).get('https_only_mode_enabled') is False:
        logger.info("Setting exists but is disabled: generated.https_only_mode_enabled = false")
        return False, "generated.https_only_mode_enabled", ""
    
    if prefs.get('https_only_mode_enabled') is False:
        logger.info("Setting exists but is disabled: https_only_mode_enabled = false")
        return False, "https_only_mode_enabled", ""
    
    if prefs.get('generated', {}).get('https_first_mode_enabled') is False:
        logger.info("Setting exists but is disabled: generated.https_first_mode_enabled = false")
        return False, "generated.https_first_mode_enabled", ""
    
    # Setting not found in any known location
    logger.info("HTTPS-Only mode setting not found in any known location")
    return None, None, ""


def validate_https_only_setting(https_enabled: Optional[bool], setting_location: Optional[str]) -> Tuple[bool, int, str]:
    """
    Validate the HTTPS-Only mode setting and generate feedback.
    
    Args:
        https_enabled: Whether HTTPS-Only mode is enabled (True/False/None)
        setting_location: Where the setting was found in Preferences
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    if https_enabled is None:
        # Setting not found at all - task definitely not completed
        return False, 0, (
            "❌ HTTPS-Only mode setting not found in Chrome Preferences.\n"
            "The setting was not configured. Please:\n"
            "  1. Navigate to chrome://settings or use menu (⋮ → Settings)\n"
            "  2. Go to Privacy and Security → Security\n"
            "  3. Enable 'Always use secure connections' toggle\n"
            "  4. Ensure Chrome saves the setting (it should be automatic)"
        )
    
    if https_enabled is False:
        # Setting exists but is explicitly disabled
        return False, 25, (
            f"❌ HTTPS-Only mode is explicitly disabled in Preferences.\n"
            f"Found at: {setting_location}\n"
            "The setting exists but is turned off. Please enable it in Chrome Settings."
        )
    
    # https_enabled is True - SUCCESS!
    return True, 100, (
        f"✅ HTTPS-Only mode successfully enabled!\n"
        f"Setting location: {setting_location}\n"
        f"Chrome will now automatically upgrade HTTP connections to HTTPS.\n"
        f"Security benefits:\n"
        f"  • All connections encrypted by default\n"
        f"  • Protection against man-in-the-middle attacks\n"
        f"  • Warning displayed when sites don't support HTTPS\n"
        f"  • Improved privacy on public WiFi networks"
    )
