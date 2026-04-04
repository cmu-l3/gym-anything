#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Media Autoplay Control Task (media_autoplay_control@1)
Task: Configure Chrome to block automatic media playback for example-news-site.com

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.sound
- Look for site pattern matching example-news-site.com
- Verify setting value is 2 (BLOCK)
- Validate URL pattern format is correct
- Ensure no side effects on other settings
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
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
    Main verification function for media_autoplay_control@1.
    
    Verifies that site-specific autoplay blocking was configured for example-news-site.com.
    
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
    target_site = task_info.get('target_site', 'example-news-site.com')
    
    try:
        # Extract autoplay settings from Chrome Preferences
        settings_found, setting_value, url_pattern, error_msg = extract_autoplay_setting(
            copy_from_env, 
            target_site
        )
        
        if not settings_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to find autoplay settings: {error_msg}"
            }
        
        # Validate the configuration
        is_valid, score, feedback = validate_autoplay_configuration(
            target_site,
            setting_value,
            url_pattern
        )
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "target_site": target_site,
                "url_pattern": url_pattern,
                "setting_value": setting_value,
                "setting_name": "BLOCK" if setting_value == 2 else "ALLOW" if setting_value == 1 else "UNKNOWN"
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_autoplay_setting(copy_from_env, target_site: str) -> Tuple[bool, Optional[int], Optional[str], str]:
    """
    Extract autoplay setting for target site from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        target_site: Target domain (e.g., 'example-news-site.com')
        
    Returns:
        Tuple of (found: bool, setting_value: int, url_pattern: str, error_message: str)
    """
    temp_file = None
    try:
        # Copy Preferences file from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
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
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return False, None, None, "Could not access Preferences file from any known location"
        
        # Navigate to content settings for sound/autoplay
        try:
            content_settings = prefs_data['profile']['content_settings']['exceptions']
            
            # Look in 'sound' settings (primary location for autoplay controls)
            sound_settings = content_settings.get('sound', {})
            
            # Search for target site in sound settings
            for pattern_key, setting_data in sound_settings.items():
                # Normalize pattern for comparison
                pattern_lower = pattern_key.lower()
                target_lower = target_site.lower()
                
                if target_lower in pattern_lower:
                    setting_value = setting_data.get('setting')
                    logger.info(f"Found setting for {target_site}: pattern={pattern_key}, value={setting_value}")
                    return True, setting_value, pattern_key, ""
            
            # Also check 'autoplay' settings if they exist separately
            autoplay_settings = content_settings.get('autoplay', {})
            for pattern_key, setting_data in autoplay_settings.items():
                pattern_lower = pattern_key.lower()
                target_lower = target_site.lower()
                
                if target_lower in pattern_lower:
                    setting_value = setting_data.get('setting')
                    logger.info(f"Found autoplay setting for {target_site}: pattern={pattern_key}, value={setting_value}")
                    return True, setting_value, pattern_key, ""
            
            return False, None, None, f"No sound/autoplay setting found for {target_site}"
            
        except KeyError as e:
            logger.error(f"Could not navigate Preferences structure: {e}")
            return False, None, None, f"Content settings structure not found in Preferences: {e}"
        
    except json.JSONDecodeError as e:
        return False, None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Error extracting autoplay setting: {e}", exc_info=True)
        return False, None, None, f"Error extracting autoplay setting: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def validate_autoplay_configuration(
    target_site: str,
    setting_value: Optional[int],
    url_pattern: Optional[str]
) -> Tuple[bool, int, str]:
    """
    Validate that autoplay configuration is correct.
    
    Checks:
    1. Site pattern was found
    2. Setting value is 2 (BLOCK)
    3. URL pattern is properly formatted
    4. Pattern matches target site
    
    Args:
        target_site: Target domain
        setting_value: Chrome setting value (2 = BLOCK, 1 = ASK/DEFAULT)
        url_pattern: Full URL pattern from Preferences
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    feedback_parts = []
    criteria_met = 0
    total_criteria = 4
    
    # Criterion 1: Site pattern exists
    if url_pattern is None:
        feedback_parts.append(f"✗ Site pattern not found: No autoplay setting configured for {target_site}")
        return False, 0, "\n".join(feedback_parts)
    else:
        feedback_parts.append(f"✓ Site pattern found: {url_pattern}")
        criteria_met += 1
    
    # Criterion 2: Setting value is BLOCK (2)
    if setting_value == 2:
        feedback_parts.append(f"✓ Setting value correct: BLOCK (value=2)")
        criteria_met += 1
    elif setting_value == 1:
        feedback_parts.append(f"✗ Setting value incorrect: ASK/DEFAULT (value=1) instead of BLOCK (value=2)")
    elif setting_value == 3:
        feedback_parts.append(f"✗ Setting value incorrect: ALLOW (value=3) instead of BLOCK (value=2)")
    else:
        feedback_parts.append(f"✗ Setting value unknown: {setting_value}")
    
    # Criterion 3: URL pattern is properly formatted
    pattern_valid = False
    if url_pattern:
        # Valid patterns include:
        # - https://example-news-site.com:443,*
        # - [*.]example-news-site.com,*
        # - https://example-news-site.com,*
        # - example-news-site.com,*
        
        pattern_formats = [
            r'https?://.*' + re.escape(target_site),  # With protocol
            r'\[\*\.\]' + re.escape(target_site),      # Wildcard subdomain
            re.escape(target_site)                      # Plain domain
        ]
        
        for pattern_format in pattern_formats:
            if re.search(pattern_format, url_pattern, re.IGNORECASE):
                pattern_valid = True
                break
        
        if pattern_valid:
            feedback_parts.append(f"✓ URL pattern properly formatted")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ URL pattern format unusual but may work: {url_pattern}")
            criteria_met += 0.5  # Partial credit
    else:
        feedback_parts.append(f"✗ URL pattern is empty")
    
    # Criterion 4: Pattern matches target site
    target_match = False
    if url_pattern and target_site.lower() in url_pattern.lower():
        feedback_parts.append(f"✓ Pattern matches target site: {target_site}")
        target_match = True
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Pattern does not match target site")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Generate final feedback
    feedback_parts.append("")
    feedback_parts.append("=" * 60)
    feedback_parts.append(f"Criteria met: {criteria_met}/{total_criteria}")
    feedback_parts.append(f"Score: {score}%")
    
    if passed:
        feedback_parts.append(f"Result: PASSED ✓")
        feedback_parts.append(f"Autoplay successfully blocked for {target_site}")
    else:
        feedback_parts.append(f"Result: FAILED ✗")
        feedback_parts.append(f"Autoplay blocking not properly configured for {target_site}")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Validation complete: passed={passed}, score={score}")
    
    return passed, score, feedback
