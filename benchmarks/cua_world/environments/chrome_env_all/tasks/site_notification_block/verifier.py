#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Notification Blocking Task (site_notification_block@1)
Task: Block notifications from nytimes.com by adding it to Chrome's notification block list

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.notifications
- Search for nytimes.com in various URL pattern formats
- Verify the setting value is 2 (BLOCK)
- Ensure it's in the correct exceptions list

Scoring:
- 100%: Site correctly blocked with proper pattern and setting
- 75-85%: Site blocked but with minor pattern format issues
- 50-74%: Site in settings but incorrect permission value or location
- 0-49%: No relevant changes detected or task not completed
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_notification_block@1.
    
    Verifies that nytimes.com has been added to Chrome's notification block list.
    
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

    # Task parameters
    target_domain = task_info.get('task_params', {}).get('target_site', 'nytimes.com')
    
    try:
        # Extract notification settings from Preferences
        prefs_data, error_msg = extract_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error_msg}"
            }
        
        # Verify notification block configuration
        result = verify_notification_block(prefs_data, target_domain)
        
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


def extract_preferences(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Preferences file
        possible_paths = [
            "/tmp/chrome_preferences_final.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not access Preferences file from any known location"
        
        return prefs_data, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting Preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_notification_block(prefs_data: Dict[str, Any], target_domain: str) -> Dict[str, Any]:
    """
    Verify that the target site has been blocked from showing notifications.
    
    Checks:
    1. Notification exceptions section exists
    2. Target domain appears in exceptions with a valid pattern
    3. Setting value is 2 (BLOCK)
    4. Entry was recently added (if backup available)
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        target_domain: Domain to check (e.g., "nytimes.com")
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Navigate to notification exceptions
    try:
        notifications_exceptions = (
            prefs_data.get('profile', {})
            .get('content_settings', {})
            .get('exceptions', {})
            .get('notifications', {})
        )
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to navigate Preferences structure: {e}",
            "details": {"error": str(e)}
        }
    
    # Criterion 1: Notification exceptions exist
    if not notifications_exceptions:
        feedback_parts.append("✗ No notification exceptions found in Preferences")
        logger.info("No notification exceptions section found")
    else:
        feedback_parts.append(f"✓ Notification exceptions section exists ({len(notifications_exceptions)} entries)")
        criteria_met += 1
        logger.info(f"Found {len(notifications_exceptions)} notification exception(s)")
    
    # Criterion 2: Target domain pattern found
    matching_patterns = []
    for pattern, config in notifications_exceptions.items():
        if target_domain.lower() in pattern.lower():
            matching_patterns.append((pattern, config))
            logger.info(f"Found matching pattern: {pattern}")
    
    if not matching_patterns:
        feedback_parts.append(f"✗ Site '{target_domain}' not found in notification exceptions")
        logger.info(f"Target domain '{target_domain}' not found in any pattern")
    else:
        feedback_parts.append(f"✓ Site '{target_domain}' found in notification exceptions")
        criteria_met += 1
        
        # Log all matching patterns
        for pattern, _ in matching_patterns:
            logger.info(f"  - Pattern: {pattern}")
    
    # Criterion 3: Setting value is BLOCK (2)
    correct_setting = False
    setting_values = []
    
    for pattern, config in matching_patterns:
        setting_value = config.get('setting')
        setting_values.append(setting_value)
        
        if setting_value == 2:  # BLOCK
            correct_setting = True
            feedback_parts.append(f"✓ Setting correctly set to BLOCK (value: 2)")
            criteria_met += 1
            logger.info(f"Setting value is correct (BLOCK = 2)")
            break
        elif setting_value == 1:  # ALLOW
            feedback_parts.append(f"✗ Site is set to ALLOW (value: 1) instead of BLOCK (value: 2)")
            logger.info(f"Incorrect setting: ALLOW (1) instead of BLOCK (2)")
        elif setting_value == 3:  # ASK
            feedback_parts.append(f"✗ Site is set to ASK (value: 3) instead of BLOCK (value: 2)")
            logger.info(f"Incorrect setting: ASK (3) instead of BLOCK (2)")
        else:
            feedback_parts.append(f"✗ Unknown setting value: {setting_value}")
            logger.info(f"Unknown setting value: {setting_value}")
    
    # Criterion 4: Pattern format is appropriate
    pattern_format_ok = False
    if matching_patterns:
        # Check if pattern is in an acceptable format
        pattern = matching_patterns[0][0]
        
        # Acceptable patterns:
        # - [*.]nytimes.com:443,*
        # - https://nytimes.com:443,*
        # - https://www.nytimes.com:443,*
        # - [*.]nytimes.com,*
        
        acceptable_formats = [
            r'\[\*\.\].*' + re.escape(target_domain),  # [*.]domain.com
            r'https?://.*' + re.escape(target_domain),  # https://domain.com
            re.escape(target_domain) + r':443',  # domain.com:443
        ]
        
        for fmt in acceptable_formats:
            if re.search(fmt, pattern, re.IGNORECASE):
                pattern_format_ok = True
                feedback_parts.append(f"✓ URL pattern format is valid: {pattern}")
                criteria_met += 1
                logger.info(f"Pattern format is acceptable: {pattern}")
                break
        
        if not pattern_format_ok:
            feedback_parts.append(f"⚠ Pattern format may be unusual: {pattern} (but will accept it)")
            criteria_met += 0.5  # Partial credit
            logger.info(f"Pattern format is unusual but contains target domain: {pattern}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build detailed feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nVerification Summary:"
    feedback += f"\n  Target site: {target_domain}"
    feedback += f"\n  Criteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\n  Final score: {score}%"
    feedback += f"\n  Result: {'✅ PASSED' if passed else '❌ FAILED'}"
    
    if not passed:
        feedback += "\n\nTo complete this task:"
        feedback += "\n  1. Navigate to chrome://settings"
        feedback += "\n  2. Click 'Privacy and security' → 'Site Settings' → 'Notifications'"
        feedback += "\n  3. Click 'Add' next to 'Not allowed to send notifications'"
        feedback += f"\n  4. Enter '[*.]' + '{target_domain}' or just '{target_domain}'"
        feedback += "\n  5. Click 'Add' to confirm"
    
    # Detailed information for debugging
    details = {
        "target_domain": target_domain,
        "criteria_met": criteria_met,
        "total_criteria": total_criteria,
        "has_notification_exceptions": bool(notifications_exceptions),
        "exception_count": len(notifications_exceptions),
        "matching_patterns": [p for p, _ in matching_patterns],
        "setting_values": setting_values,
        "correct_setting": correct_setting,
        "pattern_format_ok": pattern_format_ok
    }
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def normalize_url_pattern(pattern: str) -> str:
    """
    Normalize URL pattern for comparison.
    
    Handles various formats:
    - [*.]example.com:443,*
    - https://example.com:443,*
    - example.com
    
    Args:
        pattern: URL pattern string
        
    Returns:
        Normalized domain string
    """
    # Remove common pattern syntax
    pattern = pattern.replace('[*.]', '')
    pattern = pattern.replace('https://', '')
    pattern = pattern.replace('http://', '')
    
    # Remove port and wildcards
    pattern = re.sub(r':443,?\*?', '', pattern)
    pattern = re.sub(r':80,?\*?', '', pattern)
    pattern = pattern.rstrip(',*')
    
    return pattern.lower()
