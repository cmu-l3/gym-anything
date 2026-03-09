#!/usr/bin/env python3
"""
Verifier for Chrome Site Audio Muting Task (site_audio_mute@1)
Task: Navigate to YouTube and configure site-specific audio muting

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.sound
- Check for YouTube domain pattern in sound exceptions
- Verify setting value is 2 (BLOCK) rather than 1 (ALLOW)
- Validate that the configuration persists across sessions
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, List

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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_audio_mute@1 task.
    
    Verifies that audio has been muted for the target site (YouTube) by checking
    Chrome's Preferences file for site-specific sound permissions.
    
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

    # Get target site from task config or use default
    target_site = task_info.get('config', {}).get('target_site', 'youtube.com')
    
    try:
        # Extract sound mute settings from Chrome Preferences
        prefs_data, error_msg = extract_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error_msg}"
            }
        
        # Verify site audio muting configuration
        result = verify_site_audio_muted(prefs_data, target_site)
        
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


def extract_preferences(copy_from_env) -> Tuple[Dict, str]:
    """
    Extract Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict, error_message)
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
                    logger.info("Successfully extracted Preferences using utilities")
                    return prefs, ""
                else:
                    logger.warning("Utility-based parsing returned empty, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences_audio_mute.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Attempting to copy Preferences from: {container_path}")
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
        return None, f"Error extracting Preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_site_audio_muted(prefs_data: Dict, target_site: str) -> Dict[str, Any]:
    """
    Verify that audio is muted for the target site.
    
    Checks Chrome Preferences for sound exceptions with the target site pattern
    and validates that the setting is BLOCK (value 2).
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        target_site: Domain to check (e.g., 'youtube.com')
        
    Returns:
        Dict with verification results including passed, score, and feedback
    """
    # Criterion checks
    criteria_results = {
        "preferences_accessible": False,
        "sound_exceptions_exist": False,
        "target_site_found": False,
        "mute_setting_correct": False
    }
    
    feedback_parts = []
    
    # Criterion 1: Preferences file accessible and valid
    if prefs_data and isinstance(prefs_data, dict):
        criteria_results["preferences_accessible"] = True
        feedback_parts.append("✓ Chrome Preferences file accessed successfully")
    else:
        feedback_parts.append("✗ Chrome Preferences file not accessible or invalid")
        return build_result(criteria_results, feedback_parts, target_site)
    
    # Navigate to sound exceptions in Preferences structure
    try:
        profile = prefs_data.get('profile', {})
        content_settings = profile.get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        sound_exceptions = exceptions.get('sound', {})
    except (KeyError, AttributeError) as e:
        feedback_parts.append(f"✗ Could not navigate to sound exceptions in Preferences: {e}")
        return build_result(criteria_results, feedback_parts, target_site)
    
    # Criterion 2: Sound exceptions section exists
    if sound_exceptions and len(sound_exceptions) > 0:
        criteria_results["sound_exceptions_exist"] = True
        feedback_parts.append(f"✓ Sound exceptions found ({len(sound_exceptions)} rule(s))")
        logger.info(f"Sound exception patterns found: {list(sound_exceptions.keys())}")
    else:
        feedback_parts.append("✗ No sound exceptions configured (site permissions not modified)")
        return build_result(criteria_results, feedback_parts, target_site)
    
    # Criterion 3 & 4: Find target site and verify mute setting
    found_patterns = []
    correct_setting_count = 0
    
    for pattern_key, pattern_data in sound_exceptions.items():
        # Normalize pattern for comparison
        pattern_lower = pattern_key.lower()
        
        # Check if this pattern matches our target site
        # Chrome uses patterns like:
        # - "https://www.youtube.com:443,*"
        # - "[*.]youtube.com:443,*"
        # - "youtube.com:443,*"
        if target_site.lower() in pattern_lower:
            found_patterns.append(pattern_key)
            
            # Check the setting value
            setting_value = pattern_data.get('setting')
            last_modified = pattern_data.get('last_modified', 'unknown')
            
            logger.info(f"Found matching pattern: {pattern_key}")
            logger.info(f"  Setting value: {setting_value} (2=BLOCK, 1=ALLOW)")
            logger.info(f"  Last modified: {last_modified}")
            
            if setting_value == 2:  # BLOCK
                correct_setting_count += 1
                criteria_results["target_site_found"] = True
                criteria_results["mute_setting_correct"] = True
            elif setting_value == 1:  # ALLOW
                criteria_results["target_site_found"] = True
                feedback_parts.append(f"⚠ Found {target_site} but setting is ALLOW (not muted)")
            else:
                criteria_results["target_site_found"] = True
                feedback_parts.append(f"⚠ Found {target_site} but setting value is unexpected: {setting_value}")
    
    if criteria_results["target_site_found"] and criteria_results["mute_setting_correct"]:
        feedback_parts.append(f"✓ Audio muted for {target_site} (pattern: {found_patterns[0]})")
        feedback_parts.append(f"✓ Mute setting correctly configured (setting=2, BLOCK)")
    elif criteria_results["target_site_found"]:
        feedback_parts.append(f"✗ {target_site} found but not muted correctly")
    else:
        feedback_parts.append(f"✗ No mute configuration found for {target_site}")
        
        # Provide helpful debugging info
        if sound_exceptions:
            feedback_parts.append(f"  Found rules for other sites: {', '.join(list(sound_exceptions.keys())[:3])}")
    
    return build_result(criteria_results, feedback_parts, target_site, found_patterns)


def build_result(criteria: Dict[str, bool], feedback_parts: List[str], 
                 target_site: str, patterns: List[str] = None) -> Dict[str, Any]:
    """
    Build the final verification result dictionary.
    
    Args:
        criteria: Dict of criterion name to pass/fail boolean
        feedback_parts: List of feedback strings
        target_site: The target domain being checked
        patterns: List of matching URL patterns found (optional)
        
    Returns:
        Dict with passed, score, and feedback
    """
    # Calculate score based on criteria met
    criteria_met = sum(criteria.values())
    total_criteria = len(criteria)
    
    # Score: 100% if all 4 met, 75% if 3/4, 50% if 2/4, etc.
    score = int((criteria_met / total_criteria) * 100)
    
    # Pass threshold: need at least 3 out of 4 criteria (75%)
    passed = criteria_met >= 3
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += f"\n✅ Task PASSED: Audio successfully muted for {target_site}"
    else:
        feedback += f"\n❌ Task FAILED: Audio not properly muted for {target_site}"
        feedback += f"\n\nTo complete this task:"
        feedback += f"\n  1. Navigate to {target_site}"
        feedback += f"\n  2. Click the padlock icon in the address bar"
        feedback += f"\n  3. Click 'Site settings' or find 'Sound' permission"
        feedback += f"\n  4. Change Sound permission to 'Block'"
        feedback += f"\n  OR navigate to chrome://settings/content/sound"
        feedback += f"\n  and add {target_site} to the blocked list"
    
    # Log detailed results
    logger.info(f"Verification complete:")
    logger.info(f"  Criteria: {criteria}")
    logger.info(f"  Score: {score}%")
    logger.info(f"  Passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "target_site": target_site,
            "criteria": criteria,
            "patterns_found": patterns or [],
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
