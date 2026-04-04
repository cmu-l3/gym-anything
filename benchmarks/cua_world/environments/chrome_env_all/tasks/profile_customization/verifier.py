#!/usr/bin/env python3
"""
Verifier for Chrome Profile Customization Task (profile_customization@1)
Task: Customize Chrome profile by changing name and avatar icon

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract profile.name and profile.avatar_icon
- Validate that profile name is NOT default values ('Person 1', 'Default', etc.)
- Validate that avatar icon is NOT default value (typically index 26 or -1)
- Ensure both name and icon fields exist and are properly formatted
- Score based on 4 criteria: name changed, icon changed, fields exist

Scoring:
- 100%: All 4 criteria met (name changed, icon changed, both fields valid)
- 75%: 3/4 criteria met (one change successful)
- 50%: 2/4 criteria met (partial configuration)
- 0-49%: <2 criteria met (task failed)

Pass threshold: 75% (requires at least 3 out of 4 criteria)
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


# Default values that indicate profile hasn't been customized
DEFAULT_PROFILE_NAMES = [
    'Person 1',
    'Default',
    'Profile 1',
    'profile 1',
    'person 1',
    'default',
    '',
    'User',
    'user'
]

# Default avatar icon identifiers
# Chrome uses various formats: numeric indices, chrome://theme URIs, or string IDs
DEFAULT_AVATAR_ICONS = [
    -1,  # Unset
    0,   # Default
    26,  # Default placeholder (chrome://theme/IDR_PROFILE_AVATAR_26)
    'chrome://theme/IDR_PROFILE_AVATAR_26',
    '',  # Empty
]


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for profile_customization@1 task.
    
    Verifies that Chrome profile was customized with:
    1. Custom profile name (not default 'Person 1')
    2. Custom avatar icon (not default icon)
    
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
            "feedback": "Copy function not available in environment - cannot verify task"
        }

    try:
        # Extract profile settings from Chrome Preferences
        profile_data, error_msg = extract_profile_settings(copy_from_env)
        
        if profile_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract profile settings: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_profile_customization(profile_data)
        
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


def extract_profile_settings(copy_from_env) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Extract profile settings from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (profile_data: dict or None, error_message: str)
    """
    temp_file = None
    try:
        # Create temporary file for Preferences
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Preferences file
        preferences_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Attempting to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Extract profile section
        profile_data = prefs_data.get('profile', {})
        
        if not profile_data:
            return None, "Profile section not found in Preferences file"
        
        logger.info(f"Extracted profile data: name='{profile_data.get('name')}', avatar_icon='{profile_data.get('avatar_icon')}'")
        
        return profile_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting profile settings: {e}"
    finally:
        # Cleanup temporary file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except Exception:
                pass


def verify_profile_customization(profile_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that profile was properly customized.
    
    Checks:
    1. Profile name field exists and is properly formatted
    2. Profile name is NOT a default value
    3. Avatar icon field exists
    4. Avatar icon is NOT a default value
    
    Args:
        profile_data: Profile section from Chrome Preferences
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Extract values
    profile_name = profile_data.get('name', '')
    avatar_icon = profile_data.get('avatar_icon', None)
    
    # Criterion 1: Profile name field exists and is non-empty
    name_field_exists = 'name' in profile_data and isinstance(profile_name, str)
    if name_field_exists and len(profile_name) > 0:
        criteria_met += 1
        feedback_parts.append(f"✓ Profile name field exists: '{profile_name}'")
        logger.info("✓ Criterion 1 passed: Profile name field exists")
    else:
        feedback_parts.append("✗ Profile name field missing or empty")
        logger.info("✗ Criterion 1 failed: Profile name field missing")
    
    # Criterion 2: Profile name is customized (not default)
    name_is_custom = (
        name_field_exists and
        profile_name not in DEFAULT_PROFILE_NAMES and
        len(profile_name.strip()) > 0
    )
    if name_is_custom:
        criteria_met += 1
        feedback_parts.append(f"✓ Profile name customized to: '{profile_name}'")
        logger.info(f"✓ Criterion 2 passed: Name is custom ('{profile_name}')")
    else:
        if profile_name in DEFAULT_PROFILE_NAMES:
            feedback_parts.append(f"✗ Profile name still at default: '{profile_name}'")
        else:
            feedback_parts.append(f"⚠ Profile name unclear: '{profile_name}'")
        logger.info(f"✗ Criterion 2 failed: Name not customized ('{profile_name}')")
    
    # Criterion 3: Avatar icon field exists
    icon_field_exists = 'avatar_icon' in profile_data
    if icon_field_exists:
        criteria_met += 1
        feedback_parts.append(f"✓ Avatar icon field exists: '{avatar_icon}'")
        logger.info("✓ Criterion 3 passed: Avatar icon field exists")
    else:
        feedback_parts.append("✗ Avatar icon field missing")
        logger.info("✗ Criterion 3 failed: Avatar icon field missing")
    
    # Criterion 4: Avatar icon is customized (not default)
    icon_is_custom = False
    if icon_field_exists:
        # Normalize icon value for comparison
        if isinstance(avatar_icon, str):
            # Extract numeric ID from chrome://theme/IDR_PROFILE_AVATAR_XX format
            match = re.search(r'AVATAR[_/](\d+)', avatar_icon)
            if match:
                icon_num = int(match.group(1))
                icon_is_custom = icon_num not in DEFAULT_AVATAR_ICONS
            else:
                # String format, check if it's in defaults
                icon_is_custom = avatar_icon not in DEFAULT_AVATAR_ICONS
        elif isinstance(avatar_icon, int):
            icon_is_custom = avatar_icon not in DEFAULT_AVATAR_ICONS
        else:
            icon_is_custom = avatar_icon not in DEFAULT_AVATAR_ICONS
    
    if icon_is_custom:
        criteria_met += 1
        feedback_parts.append(f"✓ Avatar icon customized: '{avatar_icon}'")
        logger.info(f"✓ Criterion 4 passed: Icon is custom ('{avatar_icon}')")
    else:
        if icon_field_exists:
            feedback_parts.append(f"✗ Avatar icon still at default: '{avatar_icon}'")
        logger.info(f"✗ Criterion 4 failed: Icon not customized ('{avatar_icon}')")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build comprehensive feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nVerification Summary:"
    feedback += f"\n  Criteria met: {criteria_met}/{total_criteria}"
    feedback += f"\n  Score: {score}%"
    feedback += f"\n  Result: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if passed:
        if score == 100:
            feedback += "\n\n🎉 Perfect! Profile fully customized with both name and icon."
        else:
            feedback += f"\n\n✓ Task completed successfully (minor issues with {4-criteria_met} criterion/criteria)."
    else:
        feedback += "\n\n❌ Profile customization incomplete."
        if not name_is_custom:
            feedback += "\n   → Please change the profile name from default"
        if not icon_is_custom:
            feedback += "\n   → Please select a different avatar icon"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "profile_name": profile_name,
            "profile_name_customized": name_is_custom,
            "avatar_icon": str(avatar_icon),
            "avatar_icon_customized": icon_is_custom,
            "name_field_exists": name_field_exists,
            "icon_field_exists": icon_field_exists
        }
    }
