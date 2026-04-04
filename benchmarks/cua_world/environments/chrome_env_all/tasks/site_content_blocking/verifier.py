#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Content Blocking Task (site_content_blocking@1)
Task: Block JavaScript for a specific resource-heavy website to improve performance

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to navigate to profile.content_settings.exceptions.javascript
- Search for the target site URL pattern with setting value = 2 (BLOCK)
- Validate the setting is persistent (no expiration)
- Ensure no global JavaScript block (only site-specific)

Scoring:
- 100%: Perfect site-specific JavaScript block with proper persistence
- 75-99%: JavaScript blocked correctly but with minor metadata issues
- 50-74%: Setting partially configured or wrong format
- 0-49%: JavaScript not blocked or setting not found

Pass threshold: 75% (requires proper site-specific JavaScript block)
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
    
    def parse_preferences(path):
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_content_blocking@1.
    
    Verifies that JavaScript is blocked for the specific test site through
    site-specific content settings.
    
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
        # Get target site URL
        target_site = "file:///home/ga/Documents/test_heavy_site.html"
        
        # Extract JavaScript blocking settings from Preferences
        prefs_data, error_msg = extract_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error_msg}"
            }
        
        # Verify site-specific JavaScript blocking
        is_valid, score, feedback, details = verify_javascript_blocked(
            prefs_data, 
            target_site
        )
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": details
        }
        
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
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
                else:
                    logger.debug(f"File not found or empty at: {container_path}")
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not access Chrome Preferences file from any known location"
        
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


def verify_javascript_blocked(prefs_data: Dict, target_site: str) -> Tuple[bool, int, str, Dict]:
    """
    Verify that JavaScript is blocked for the specific target site.
    
    Checks:
    1. JavaScript exception exists for target site
    2. Setting value is 2 (BLOCK), not 1 (ALLOW) or 0 (ASK)
    3. Setting is persistent (no expiration)
    4. Only site-specific block (not global JavaScript disable)
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        target_site: Target site URL to check
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str, details: dict)
    """
    # Initialize tracking variables
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    details = {
        "target_site": target_site,
        "javascript_exceptions_found": False,
        "site_specific_block_found": False,
        "correct_setting_value": False,
        "persistent_setting": False,
        "not_global_block": True
    }
    
    # Navigate to JavaScript exceptions in Preferences
    try:
        content_settings = prefs_data.get('profile', {}).get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        js_exceptions = exceptions.get('javascript', {})
    except Exception as e:
        feedback = f"✗ Could not navigate to content_settings.exceptions.javascript in Preferences: {e}"
        return False, 0, feedback, details
    
    if not js_exceptions:
        feedback = "✗ No JavaScript exceptions found in Preferences. The site-specific setting was not created."
        feedback += "\n\nTo complete this task:"
        feedback += "\n  1. Click the padlock icon in the address bar"
        feedback += "\n  2. Click 'Site settings'"
        feedback += "\n  3. Find 'JavaScript' and change it to 'Block'"
        return False, 0, feedback, details
    
    details["javascript_exceptions_found"] = True
    criteria_met += 1
    feedback_parts.append("✓ JavaScript exceptions section exists in Preferences")
    
    # Look for the target site with various URL pattern formats
    # Chrome stores site-specific permissions with patterns like:
    # - "file:///path/to/file.html,*"
    # - "file:///path/to/file.html:*,*"
    # - "file://*,*" (too broad)
    
    # Normalize target site for comparison
    normalized_target = normalize_file_url(target_site)
    logger.info(f"Searching for JavaScript block for: {normalized_target}")
    logger.info(f"Found {len(js_exceptions)} JavaScript exception(s)")
    
    # Check all JavaScript exceptions
    site_found = False
    correct_value = False
    is_persistent = False
    matched_pattern = None
    
    for pattern, setting_data in js_exceptions.items():
        logger.info(f"Checking pattern: {pattern}")
        logger.info(f"  Setting data: {setting_data}")
        
        # Check if this pattern matches our target site
        if is_pattern_match(pattern, normalized_target):
            site_found = True
            matched_pattern = pattern
            details["site_specific_block_found"] = True
            
            # Check setting value (2 = BLOCK)
            setting_value = setting_data.get('setting')
            if setting_value == 2:
                correct_value = True
                details["correct_setting_value"] = True
                feedback_parts.append(f"✓ JavaScript blocked for target site (pattern: {pattern})")
            elif setting_value == 1:
                feedback_parts.append(f"✗ JavaScript is ALLOWED (not blocked) for target site (pattern: {pattern})")
            else:
                feedback_parts.append(f"⚠ JavaScript setting has unexpected value: {setting_value} (pattern: {pattern})")
            
            # Check if setting is persistent (no expiration or far future expiration)
            expiration = setting_data.get('expiration', 0)
            if expiration == 0 or expiration > 9999999999:  # 0 means no expiration
                is_persistent = True
                details["persistent_setting"] = True
                feedback_parts.append("✓ Setting is persistent (no expiration)")
            else:
                feedback_parts.append(f"⚠ Setting has expiration: {expiration}")
            
            break
    
    if site_found and correct_value:
        criteria_met += 1  # Site-specific block found with correct value
    elif site_found and not correct_value:
        feedback_parts.append("✗ Site-specific setting exists but JavaScript is not blocked")
    else:
        feedback_parts.append(f"✗ No JavaScript block found for target site: {target_site}")
        feedback_parts.append(f"   Found patterns: {list(js_exceptions.keys())}")
    
    if correct_value:
        criteria_met += 1  # Correct setting value
    
    if is_persistent:
        criteria_met += 1  # Persistent setting
    
    # Check that it's not a global JavaScript disable
    # Global disable would be indicated by webkit.webprefs.javascript_enabled = false
    try:
        webkit_prefs = prefs_data.get('webkit', {}).get('webprefs', {})
        js_enabled = webkit_prefs.get('javascript_enabled', True)
        
        if js_enabled is False:
            details["not_global_block"] = False
            feedback_parts.append("⚠ JavaScript is globally disabled, not just site-specific")
            # Don't fail entirely, but don't count this criterion
        else:
            # Global JavaScript is still enabled - good!
            pass
    except Exception as e:
        logger.warning(f"Could not check global JavaScript setting: {e}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\n📋 How to complete this task:"
        feedback += "\n  1. Navigate to the test site (file:///home/ga/Documents/test_heavy_site.html)"
        feedback += "\n  2. Click the padlock/info icon in the address bar (left of URL)"
        feedback += "\n  3. Click 'Site settings' in the popup"
        feedback += "\n  4. Scroll to find 'JavaScript' permission"
        feedback += "\n  5. Change JavaScript from 'Allow' to 'Block'"
        feedback += "\n  6. Close the settings tab - the change saves automatically"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return passed, score, feedback, details


def normalize_file_url(url: str) -> str:
    """
    Normalize a file:// URL for comparison.
    
    Args:
        url: URL to normalize
        
    Returns:
        Normalized URL string
    """
    # Remove trailing slashes
    url = url.rstrip('/')
    # Ensure lowercase
    url = url.lower()
    # Ensure file:// protocol
    if not url.startswith('file://'):
        url = 'file://' + url
    return url


def is_pattern_match(pattern: str, target_url: str) -> bool:
    """
    Check if a Chrome content setting pattern matches the target URL.
    
    Chrome uses patterns like:
    - "file:///path/to/file.html,*"
    - "file:///path/to/file.html:*,*"
    - "https://example.com:*,*"
    
    Args:
        pattern: Chrome content setting pattern
        target_url: Target URL to match against
        
    Returns:
        True if pattern matches target URL
    """
    # Normalize both for comparison
    pattern_lower = pattern.lower()
    target_lower = target_url.lower()
    
    # Remove the trailing pattern suffixes that Chrome adds
    # Common patterns: ",*" or ":*,*"
    pattern_base = re.sub(r'[:,]\*+$', '', pattern_lower)
    pattern_base = pattern_base.rstrip(',')
    
    # Check for exact match or prefix match
    if target_lower.startswith(pattern_base):
        return True
    
    # Check if pattern is contained in target (for file:// URLs)
    if 'file://' in pattern_lower and 'file://' in target_lower:
        # Extract the file path part
        pattern_path = pattern_base.replace('file://', '')
        target_path = target_lower.replace('file://', '')
        
        if pattern_path in target_path or target_path in pattern_path:
            return True
    
    return False
