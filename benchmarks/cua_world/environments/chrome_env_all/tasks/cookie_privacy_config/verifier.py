#!/usr/bin/env python3
"""
Verifier for Chrome Third-Party Cookie Blocking Configuration Task (cookie_privacy_config@1)
Task: Configure Chrome to block third-party cookies for enhanced privacy

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract cookie-related settings
- Validate that third-party cookie blocking is enabled
- Check multiple cookie policy indicators for robustness
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'utils'))
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
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for cookie_privacy_config@1.
    
    Verifies that Chrome's third-party cookie blocking has been enabled.
    
    Verification Criteria (4 total, need 3+ to pass at 75%):
    1. Preferences file accessible
    2. Cookie policy modified from default
    3. Third-party blocking enabled (cookie_controls_mode >= 1 OR block_third_party_cookies = true)
    4. Configuration is valid (no corrupted values)
    
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
        # Extract cookie settings from Chrome Preferences
        cookie_settings, error_msg = extract_cookie_settings(copy_from_env)
        
        if cookie_settings is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract cookie settings: {error_msg}"
            }
        
        # Validate cookie blocking configuration
        result = validate_cookie_blocking(cookie_settings)
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_cookie_settings(copy_from_env) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Extract cookie-related settings from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (cookie_settings dict or None, error_message)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
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
                    cookie_settings = extract_cookie_fields_from_prefs(prefs)
                    return cookie_settings, ""
                else:
                    logger.warning("Failed to parse preferences with utility, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences.json",
            "/tmp/chrome_preferences_after.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_path = None
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            return None, "Could not access Preferences file from any known location"
        
        # Extract cookie-related fields
        cookie_settings = extract_cookie_fields_from_prefs(prefs)
        
        logger.info(f"Extracted cookie settings: {cookie_settings}")
        
        return cookie_settings, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting cookie settings: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_cookie_fields_from_prefs(prefs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract relevant cookie configuration fields from parsed Preferences.
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Dictionary with cookie-related settings
    """
    profile = prefs.get('profile', {})
    
    # Primary method: cookie_controls_mode (modern Chrome)
    # 0 = allow all cookies
    # 1 = block third-party cookies
    # 2 = block third-party cookies in Incognito mode only
    cookie_controls_mode = profile.get('cookie_controls_mode', 0)
    
    # Alternative method: block_third_party_cookies flag (older Chrome versions)
    block_third_party = profile.get('block_third_party_cookies', False)
    
    # Content settings for cookies (global default)
    content_settings = profile.get('default_content_setting_values', {})
    cookies_default = content_settings.get('cookies', 1)  # 1=allow, 2=block, 4=session_only
    
    # Check if there are any cookie exceptions (sites allowed/blocked specifically)
    exceptions = profile.get('content_settings', {}).get('exceptions', {}).get('cookies', {})
    has_exceptions = len(exceptions) > 0
    
    return {
        'cookie_controls_mode': cookie_controls_mode,
        'block_third_party_cookies': block_third_party,
        'default_cookies_setting': cookies_default,
        'has_exceptions': has_exceptions,
        'exception_count': len(exceptions)
    }


def validate_cookie_blocking(cookie_settings: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate that third-party cookie blocking has been properly configured.
    
    Verification Criteria:
    1. Preferences file accessible (already verified if we got here)
    2. Cookie policy modified from default (cookie_controls_mode != 0 OR other changes)
    3. Third-party blocking enabled (cookie_controls_mode >= 1 OR block_third_party_cookies = true)
    4. Configuration is valid (values are within expected ranges)
    
    Args:
        cookie_settings: Dictionary with extracted cookie settings
        
    Returns:
        Verification result dict with passed, score, and detailed feedback
    """
    criteria_met = []
    feedback_details = []
    
    # Extract settings
    cookie_controls_mode = cookie_settings.get('cookie_controls_mode', 0)
    block_third_party = cookie_settings.get('block_third_party_cookies', False)
    cookies_default = cookie_settings.get('default_cookies_setting', 1)
    
    # Criterion 1: Preferences file accessible (implicit - we got this far)
    criteria_met.append(True)
    feedback_details.append("✓ Preferences file successfully accessed")
    
    # Criterion 2: Cookie policy modified from defaults
    is_modified = (cookie_controls_mode != 0) or block_third_party or (cookies_default != 1)
    criteria_met.append(is_modified)
    
    if is_modified:
        feedback_details.append("✓ Cookie policy has been modified from defaults")
    else:
        feedback_details.append("✗ Cookie policy appears unchanged from default 'allow all'")
    
    # Criterion 3: Third-party blocking enabled (PRIMARY CRITERION)
    # cookie_controls_mode: 0=off, 1=block_third_party, 2=block_third_party_incognito
    third_party_blocked = (cookie_controls_mode >= 1) or block_third_party
    criteria_met.append(third_party_blocked)
    
    if cookie_controls_mode == 1:
        feedback_details.append("✓ Third-party cookies fully blocked (cookie_controls_mode=1)")
    elif cookie_controls_mode == 2:
        feedback_details.append("✓ Third-party cookies blocked in Incognito mode (cookie_controls_mode=2)")
    elif block_third_party:
        feedback_details.append("✓ Third-party cookies blocked (legacy flag enabled)")
    else:
        feedback_details.append("✗ Third-party cookie blocking not detected")
        feedback_details.append(f"  Current cookie_controls_mode: {cookie_controls_mode} (expected >= 1)")
    
    # Criterion 4: Configuration is valid
    valid_cookie_controls = cookie_controls_mode in [0, 1, 2]
    valid_cookies_setting = cookies_default in [1, 2, 4]  # 1=allow, 2=block, 4=session_only
    configuration_valid = valid_cookie_controls and valid_cookies_setting
    
    criteria_met.append(configuration_valid)
    
    if configuration_valid:
        feedback_details.append("✓ Cookie configuration values are valid")
    else:
        feedback_details.append(f"✗ Cookie configuration contains invalid values")
        if not valid_cookie_controls:
            feedback_details.append(f"  Invalid cookie_controls_mode: {cookie_controls_mode}")
        if not valid_cookies_setting:
            feedback_details.append(f"  Invalid default cookies setting: {cookies_default}")
    
    # Calculate score
    criteria_score = sum(criteria_met)
    total_criteria = len(criteria_met)
    score = int((criteria_score / total_criteria) * 100)
    
    # Determine pass/fail (need 75% = 3/4 criteria)
    # Most importantly, criterion 3 (third_party_blocked) must be True
    passed = score >= 75 and third_party_blocked
    
    # Additional information for detailed feedback
    mode_descriptions = {
        0: "Allow all cookies (default)",
        1: "Block third-party cookies (recommended)",
        2: "Block third-party cookies in Incognito mode only"
    }
    
    mode_str = mode_descriptions.get(cookie_controls_mode, f"Unknown mode ({cookie_controls_mode})")
    
    if passed:
        feedback_details.append(f"\n📊 Configuration Summary:")
        feedback_details.append(f"  Policy: {mode_str}")
        feedback_details.append(f"  Score: {score}% ({criteria_score}/{total_criteria} criteria met)")
        feedback_details.append(f"\n✅ Task completed successfully!")
        feedback_details.append("Third-party cookie blocking is now enabled, enhancing your privacy.")
    else:
        feedback_details.append(f"\n📊 Configuration Summary:")
        feedback_details.append(f"  Current policy: {mode_str}")
        feedback_details.append(f"  Score: {score}% ({criteria_score}/{total_criteria} criteria met)")
        feedback_details.append(f"\n❌ Task incomplete")
        
        if not third_party_blocked:
            feedback_details.append("\nRequired action:")
            feedback_details.append("  Navigate to chrome://settings/cookies")
            feedback_details.append("  Select 'Block third-party cookies' option")
    
    feedback = "\n".join(feedback_details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "cookie_controls_mode": cookie_controls_mode,
            "block_third_party_cookies": block_third_party,
            "default_cookies_setting": cookies_default,
            "criteria_met": criteria_score,
            "total_criteria": total_criteria,
            "third_party_blocked": third_party_blocked
        }
    }
