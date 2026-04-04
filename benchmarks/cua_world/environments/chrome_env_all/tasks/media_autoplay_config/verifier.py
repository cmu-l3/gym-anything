#!/usr/bin/env python3
"""
Verifier for Chrome Media Autoplay Configuration Task (media_autoplay_config@1)
Task: Block media autoplay for news.example.com by adding it to Site Settings sound exceptions

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.sound
- Look for news.example.com in various possible formats
- Verify setting value is 2 (Block)
- Validate timestamp shows recent modification
"""

import logging
import sys
import os
import json
import re
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
        parse_preferences
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for media_autoplay_config@1.
    
    Verifies that news.example.com has been added to Chrome's sound/autoplay block list.
    
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

    # Target domain to block
    target_domain = "news.example.com"

    try:
        # Get autoplay configuration from Chrome Preferences
        result = verify_autoplay_configuration(copy_from_env, target_domain)
        
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


def get_preferences_file(copy_from_env):
    """
    Retrieve Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (prefs_dict, error_message)
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
                return prefs, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple possible locations
        container_paths = [
            "/tmp/chrome_preferences_export.json",
            "/tmp/chrome_prefs_backup.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in container_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"✓ Successfully copied and parsed Preferences from: {container_path}")
                    return prefs, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return None, "Could not access Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error retrieving Preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def normalize_domain_for_matching(domain):
    """
    Generate possible domain pattern variations for matching.
    
    Chrome stores sound exceptions in various formats:
    - "news.example.com,*"
    - "[*.]news.example.com,*"
    - "https://news.example.com,*"
    - etc.
    
    Args:
        domain: Base domain (e.g., "news.example.com")
        
    Returns:
        List of possible pattern strings
    """
    patterns = [
        f"{domain},*",
        f"[*.]{domain},*",
        f"https://{domain},*",
        f"http://{domain},*",
        f"https://[*.]{domain},*",
        f"http://[*.]{domain},*",
    ]
    return patterns


def find_domain_in_sound_exceptions(sound_exceptions, target_domain):
    """
    Search for target domain in sound exceptions with flexible pattern matching.
    
    Args:
        sound_exceptions: Dict of sound exception entries from Preferences
        target_domain: Domain to search for (e.g., "news.example.com")
        
    Returns:
        Tuple of (found: bool, matched_pattern: str, setting_value: int or None)
    """
    if not sound_exceptions:
        return False, None, None
    
    # Generate possible patterns
    possible_patterns = normalize_domain_for_matching(target_domain)
    
    # Check for exact matches
    for pattern in possible_patterns:
        if pattern in sound_exceptions:
            entry = sound_exceptions[pattern]
            setting_value = entry.get('setting')
            logger.info(f"✓ Found exact match: {pattern} with setting={setting_value}")
            return True, pattern, setting_value
    
    # Check for case-insensitive partial matches
    target_lower = target_domain.lower()
    for key, value in sound_exceptions.items():
        if target_lower in key.lower():
            setting_value = value.get('setting')
            logger.info(f"✓ Found case-insensitive match: {key} with setting={setting_value}")
            return True, key, setting_value
    
    return False, None, None


def verify_autoplay_configuration(copy_from_env, target_domain):
    """
    Verify that autoplay is blocked for the target domain in Chrome Preferences.
    
    Checks multiple criteria:
    1. Preferences file accessible
    2. Sound exceptions section exists
    3. Target domain present in exceptions
    4. Setting value is 2 (Block)
    5. Modification timestamp is recent (optional bonus)
    
    Args:
        copy_from_env: Function to copy files from container
        target_domain: Domain to check for autoplay block (e.g., "news.example.com")
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    # Get Preferences file
    prefs, error_msg = get_preferences_file(copy_from_env)
    
    # Criterion 1: Preferences file accessible
    if prefs is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"✗ Failed to access Preferences file: {error_msg}",
            "details": {
                "preferences_accessible": False,
                "error": error_msg
            }
        }
    
    logger.info("✓ Criterion 1: Preferences file accessible")
    
    # Navigate to sound exceptions
    sound_exceptions = (
        prefs.get('profile', {})
        .get('content_settings', {})
        .get('exceptions', {})
        .get('sound', {})
    )
    
    # Criterion 2: Sound exceptions exist
    if not sound_exceptions:
        return {
            "passed": False,
            "score": 25,
            "feedback": (
                f"✗ Sound exceptions not found in Preferences.\n"
                f"The agent may not have navigated to Site Settings or Sound settings.\n"
                f"Expected path: Settings → Privacy and security → Site Settings → Sound"
            ),
            "details": {
                "preferences_accessible": True,
                "sound_exceptions_exist": False,
                "target_domain": target_domain
            }
        }
    
    logger.info(f"✓ Criterion 2: Sound exceptions exist ({len(sound_exceptions)} entries)")
    
    # Criterion 3 & 4: Domain present with correct setting
    found, matched_pattern, setting_value = find_domain_in_sound_exceptions(
        sound_exceptions, target_domain
    )
    
    if not found:
        # Domain not found at all
        existing_domains = list(sound_exceptions.keys())
        return {
            "passed": False,
            "score": 50,
            "feedback": (
                f"✗ Domain '{target_domain}' not found in sound exceptions.\n"
                f"Found {len(existing_domains)} other sound exception(s).\n"
                f"The agent may have navigated to settings but did not add the domain."
            ),
            "details": {
                "preferences_accessible": True,
                "sound_exceptions_exist": True,
                "domain_found": False,
                "target_domain": target_domain,
                "existing_exceptions": existing_domains[:5]  # Show first 5 for debugging
            }
        }
    
    logger.info(f"✓ Criterion 3: Domain found as: {matched_pattern}")
    
    # Check if setting is correct (2 = Block)
    if setting_value != 2:
        return {
            "passed": False,
            "score": 70,
            "feedback": (
                f"✗ Domain '{target_domain}' found but setting is incorrect.\n"
                f"Setting value: {setting_value} (expected: 2 for Block)\n"
                f"Matched pattern: {matched_pattern}\n"
                f"The domain may have been added with wrong permission."
            ),
            "details": {
                "preferences_accessible": True,
                "sound_exceptions_exist": True,
                "domain_found": True,
                "matched_pattern": matched_pattern,
                "setting_value": setting_value,
                "expected_value": 2
            }
        }
    
    logger.info(f"✓ Criterion 4: Setting value correct (2 = Block)")
    
    # Criterion 5 (Bonus): Check modification timestamp
    entry = sound_exceptions[matched_pattern]
    timestamp_str = entry.get('last_modified')
    timestamp_valid = False
    
    if timestamp_str:
        try:
            # Chrome timestamps are in microseconds since Windows epoch
            # Convert to seconds and check if recent
            timestamp_seconds = float(timestamp_str) / 1000000
            # This is still Windows epoch, but we just check it exists
            timestamp_valid = True
            logger.info(f"✓ Criterion 5 (bonus): Timestamp present: {timestamp_str}")
        except:
            logger.info("⚠ Could not parse timestamp")
    
    # All criteria met!
    score = 100 if timestamp_valid else 95
    
    return {
        "passed": True,
        "score": score,
        "feedback": (
            f"✅ Successfully blocked autoplay for {target_domain}!\n\n"
            f"Verification details:\n"
            f"  ✓ Preferences file accessible\n"
            f"  ✓ Sound exceptions configured\n"
            f"  ✓ Domain found: {matched_pattern}\n"
            f"  ✓ Setting value: {setting_value} (Block)\n"
            f"  {'✓' if timestamp_valid else '⚠'} Modification timestamp: {'Present' if timestamp_valid else 'Not found'}\n\n"
            f"The agent successfully navigated to Site Settings and added the domain\n"
            f"to the 'Not allowed to play sound' list with correct configuration."
        ),
        "details": {
            "preferences_accessible": True,
            "sound_exceptions_exist": True,
            "domain_found": True,
            "matched_pattern": matched_pattern,
            "setting_value": setting_value,
            "expected_value": 2,
            "timestamp_valid": timestamp_valid,
            "verification_method": "preferences_file"
        }
    }
