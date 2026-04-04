#!/usr/bin/env python3
"""
Verifier for Chrome Form Recovery / Autofill Profile Setup Task (form_recovery_session@1)

Task: Set up comprehensive Chrome autofill profile to prevent form data loss
Scenario: User lost form data to session timeout, needs prevention for future

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to locate autofill.profiles array
- Verify at least one complete profile exists
- Check essential fields are filled (name, email, phone, address)
- Validate data quality (not placeholder/test values)
- Ensure autofill is enabled
- Score based on completeness and data quality
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Essential fields that should be present in a comprehensive autofill profile
ESSENTIAL_FIELDS = [
    'name_first',
    'name_last', 
    'email',
    'phone_home_whole_number',
    'address_home_line1',
    'address_home_city',
    'address_home_state',
    'address_home_zip',
    'address_home_country'
]

# Optional but recommended fields
OPTIONAL_FIELDS = [
    'name_middle',
    'address_home_line2',
    'company_name'
]

# Placeholder values to reject (indicates test data, not real profile)
PLACEHOLDER_VALUES = [
    'test', 'example', 'placeholder', 'xxx', 'abc', '123', 
    'asdf', 'qwerty', 'sample', 'demo', 'fake', 'dummy'
]

# Regex patterns for field validation
EMAIL_PATTERN = re.compile(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
PHONE_PATTERN = re.compile(r'\d{7,}')  # At least 7 digits
ZIP_PATTERN = re.compile(r'\d{5}(-\d{4})?|[A-Z]\d[A-Z]\s?\d[A-Z]\d')  # US or Canadian format


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for form_recovery_session@1 task.
    
    Verifies that agent has created a comprehensive, realistic autofill profile
    to prevent future form data loss.
    
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

    try:
        # Extract autofill profile from Chrome Preferences
        profile_data, error_msg = extract_autofill_profile(copy_from_env)
        
        if profile_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract autofill profile: {error_msg}"
            }
        
        # Check if autofill is enabled
        autofill_enabled = profile_data.get('autofill_enabled', False)
        profiles = profile_data.get('profiles', [])
        
        if not autofill_enabled:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Autofill feature is not enabled. Please enable 'Save and fill addresses' in chrome://settings/addresses"
            }
        
        if not profiles or len(profiles) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No autofill profiles found. Please create an address profile in chrome://settings/addresses"
            }
        
        # Analyze the most complete profile (user may have created multiple)
        best_profile = max(profiles, key=lambda p: len(p.keys()))
        
        # Perform comprehensive validation
        validation_result = validate_autofill_profile(best_profile)
        
        # Clean up
        cleanup_verification_temp()
        
        return validation_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_autofill_profile(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract autofill profile data from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (profile_data: Dict or None, error_message: str)
        profile_data contains: {
            'autofill_enabled': bool,
            'profiles': List[Dict]
        }
    """
    temp_file = None
    try:
        # Create temporary file for copying
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_autofill.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs is None:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Extract autofill data
        autofill_section = prefs.get('autofill', {})
        
        # Check if autofill is enabled
        autofill_enabled = autofill_section.get('profile_enabled', True)  # True by default in Chrome
        
        # Get profiles array
        profiles = autofill_section.get('profiles', [])
        
        logger.info(f"Extracted {len(profiles)} autofill profile(s), autofill_enabled={autofill_enabled}")
        
        return {
            'autofill_enabled': autofill_enabled,
            'profiles': profiles
        }, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting autofill profile: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def validate_autofill_profile(profile: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate the quality and completeness of an autofill profile.
    
    Checks:
    1. Essential fields are present and filled
    2. Data quality (not placeholder values)
    3. Format validation (email, phone, zip)
    4. Completeness score (% of fields filled)
    5. Overall quality assessment
    
    Args:
        profile: Autofill profile dictionary with field keys and values
        
    Returns:
        Dict with passed, score, feedback, and detailed analysis
    """
    feedback_parts = []
    issues = []
    
    # Count filled essential fields
    essential_filled = 0
    essential_issues = []
    
    for field in ESSENTIAL_FIELDS:
        value = profile.get(field, '').strip()
        
        if not value:
            essential_issues.append(f"Missing {field.replace('_', ' ')}")
            continue
        
        # Check if it's a placeholder
        if is_placeholder_value(value):
            essential_issues.append(f"{field.replace('_', ' ')} contains placeholder/test value: '{value}'")
            continue
        
        # Validate format for specific fields
        if field == 'email' and not EMAIL_PATTERN.match(value):
            essential_issues.append(f"Invalid email format: '{value}'")
            continue
        
        if field == 'phone_home_whole_number' and not PHONE_PATTERN.search(value):
            essential_issues.append(f"Invalid phone format: '{value}'")
            continue
        
        if field == 'address_home_zip' and not ZIP_PATTERN.match(value):
            essential_issues.append(f"Invalid ZIP code format: '{value}'")
            continue
        
        # Field is valid
        essential_filled += 1
    
    # Calculate completeness ratio
    essential_completeness = essential_filled / len(ESSENTIAL_FIELDS)
    
    # Count optional fields filled
    optional_filled = 0
    for field in OPTIONAL_FIELDS:
        value = profile.get(field, '').strip()
        if value and not is_placeholder_value(value):
            optional_filled += 1
    
    # Calculate base score
    if essential_filled == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No valid essential fields filled. Please create a complete autofill profile in chrome://settings/addresses",
            "details": {
                "essential_filled": 0,
                "essential_total": len(ESSENTIAL_FIELDS),
                "issues": ["Profile is empty or contains only invalid data"]
            }
        }
    
    # Score calculation
    # Base score from essential fields (0-85 points)
    base_score = int(essential_completeness * 85)
    
    # Bonus points for optional fields (up to 15 points)
    optional_bonus = int((optional_filled / len(OPTIONAL_FIELDS)) * 15)
    
    total_score = base_score + optional_bonus
    
    # Apply penalties for quality issues
    quality_penalty = min(len(essential_issues) * 5, 20)  # Max 20 point penalty
    final_score = max(0, total_score - quality_penalty)
    
    # Determine pass/fail (need 85% = at least 6/9 essential fields + good quality)
    passed = final_score >= 85
    
    # Generate detailed feedback
    feedback_parts.append(f"Autofill Profile Verification Results:")
    feedback_parts.append(f"")
    feedback_parts.append(f"Essential Fields: {essential_filled}/{len(ESSENTIAL_FIELDS)} filled correctly")
    
    if essential_issues:
        feedback_parts.append(f"")
        feedback_parts.append(f"Issues Found:")
        for issue in essential_issues[:5]:  # Show max 5 issues
            feedback_parts.append(f"  ✗ {issue}")
        if len(essential_issues) > 5:
            feedback_parts.append(f"  ... and {len(essential_issues) - 5} more issues")
    
    if optional_filled > 0:
        feedback_parts.append(f"")
        feedback_parts.append(f"Optional Fields: {optional_filled}/{len(OPTIONAL_FIELDS)} filled")
    
    feedback_parts.append(f"")
    feedback_parts.append(f"Completeness: {int(essential_completeness * 100)}%")
    feedback_parts.append(f"Final Score: {final_score}/100")
    
    if passed:
        feedback_parts.append(f"")
        feedback_parts.append(f"✅ Excellent! Comprehensive autofill profile created.")
        feedback_parts.append(f"This will prevent future form data loss by auto-filling forms with one click.")
    elif final_score >= 70:
        feedback_parts.append(f"")
        feedback_parts.append(f"⚠ Good progress, but profile needs improvement.")
        feedback_parts.append(f"Add missing fields or fix invalid data to reach 85% threshold.")
    else:
        feedback_parts.append(f"")
        feedback_parts.append(f"❌ Profile is incomplete or contains too many issues.")
        feedback_parts.append(f"Please create a comprehensive profile with realistic information.")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback,
        "details": {
            "essential_filled": essential_filled,
            "essential_total": len(ESSENTIAL_FIELDS),
            "optional_filled": optional_filled,
            "optional_total": len(OPTIONAL_FIELDS),
            "completeness": int(essential_completeness * 100),
            "issues": essential_issues,
            "profile_field_count": len(profile.keys())
        }
    }


def is_placeholder_value(value: str) -> bool:
    """
    Check if a value appears to be a placeholder/test value.
    
    Args:
        value: String value to check
        
    Returns:
        True if value is likely a placeholder, False if it seems realistic
    """
    if not value:
        return True
    
    value_lower = value.lower().strip()
    
    # Check against known placeholder values
    for placeholder in PLACEHOLDER_VALUES:
        if placeholder in value_lower:
            return True
    
    # Check for obviously fake patterns
    if value_lower in ['a', 'aa', 'aaa', 'n/a', 'na', 'none', 'null']:
        return True
    
    # Check for repeated characters (like "aaaa" or "1111")
    if len(value) >= 3 and len(set(value)) == 1:
        return True
    
    # Check for sequential patterns
    if value_lower in ['abc', '123', 'abcd', '1234', 'abcde', '12345']:
        return True
    
    return False
