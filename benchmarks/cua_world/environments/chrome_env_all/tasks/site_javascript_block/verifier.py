#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific JavaScript Blocking Task (site_javascript_block@1)
Task: Block JavaScript for example.com using Chrome's site-specific content settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.javascript
- Check if example.com (or pattern variants) is in the blocked list
- Verify permission value is 2 (BLOCK) not 1 (ALLOW)
- Ensure JavaScript wasn't disabled globally (default setting unchanged)
- Validate configuration persistence and integrity
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
    
    def parse_preferences(path):
        """Fallback implementation"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback implementation"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for site_javascript_block@1.
    
    Verifies that JavaScript blocking rule was correctly configured for example.com.
    
    Criteria (5 total, need 4+ to pass):
    1. Preferences file accessible and parseable
    2. JavaScript exception found for target site
    3. Correct site pattern (example.com or variant)
    4. Block permission set (setting = 2)
    5. Not global block (default JavaScript still enabled)
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    target_site = "example.com"
    
    try:
        # Extract Preferences data from container
        prefs_data, error_msg = extract_preferences_file(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Preferences file: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_javascript_blocking(prefs_data, target_site)
        
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


def extract_preferences_file(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Chrome Preferences file from container.
    
    Tries multiple possible locations and handles various edge cases.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict, error_message)
    """
    # Try multiple possible locations in order of preference
    possible_paths = [
        "/tmp/chrome_preferences_final.json",
        "/home/ga/.config/google-chrome-cdp/Default/Preferences",
        "/home/ga/.config/google-chrome/Default/Preferences",
        "/tmp/chrome_preferences_backup.json"
    ]
    
    for container_path in possible_paths:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
            temp_path = temp_file.name
            temp_file.close()
            
            logger.info(f"Attempting to copy Preferences from: {container_path}")
            copy_from_env(container_path, temp_path)
            
            # Check if file was copied successfully and has content
            if os.path.exists(temp_path) and os.path.getsize(temp_path) > 10:
                with open(temp_path, 'r', encoding='utf-8') as f:
                    prefs_data = json.load(f)
                
                os.unlink(temp_path)
                logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                return prefs_data, ""
            else:
                logger.debug(f"File from {container_path} is empty or invalid")
                if os.path.exists(temp_path):
                    os.unlink(temp_path)
                    
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse JSON from {container_path}: {e}")
            if os.path.exists(temp_path):
                os.unlink(temp_path)
        except Exception as e:
            logger.debug(f"Failed to copy from {container_path}: {e}")
            if 'temp_path' in locals() and os.path.exists(temp_path):
                os.unlink(temp_path)
            continue
    
    return None, "Could not access Preferences file from any known location"


def verify_javascript_blocking(prefs_data: Dict[str, Any], target_site: str) -> Dict[str, Any]:
    """
    Verify JavaScript blocking configuration in Preferences.
    
    Checks multiple criteria to ensure proper configuration.
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        target_site: Expected blocked site (e.g., "example.com")
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Preferences file accessible (already met if we got here)
    criteria_met += 1
    feedback_parts.append("✓ Preferences file accessible and parseable")
    
    # Navigate to JavaScript exceptions in preferences structure
    try:
        profile = prefs_data.get('profile', {})
        content_settings = profile.get('content_settings', {})
        exceptions = content_settings.get('exceptions', {})
        javascript_exceptions = exceptions.get('javascript', {})
        
        logger.info(f"Found {len(javascript_exceptions)} JavaScript exception(s)")
        
        if not javascript_exceptions:
            feedback_parts.append("✗ No JavaScript exceptions found in Preferences")
            logger.warning("JavaScript exceptions object is empty")
        else:
            # Log all JavaScript exceptions for debugging
            for pattern, settings in javascript_exceptions.items():
                logger.info(f"  JavaScript exception: {pattern} -> setting={settings.get('setting')}")
        
    except Exception as e:
        logger.error(f"Failed to navigate Preferences structure: {e}")
        feedback_parts.append(f"✗ Failed to access JavaScript exceptions in Preferences: {e}")
        
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": "\n".join(feedback_parts),
            "details": {
                "criteria_met": criteria_met,
                "total_criteria": total_criteria
            }
        }
    
    # Criterion 2 & 3: Find target site with correct pattern
    site_found = False
    found_pattern = None
    setting_value = None
    
    # Generate possible URL patterns Chrome might use
    possible_patterns = generate_url_patterns(target_site)
    logger.info(f"Looking for patterns: {possible_patterns}")
    
    for pattern in possible_patterns:
        if pattern in javascript_exceptions:
            site_found = True
            found_pattern = pattern
            exception_data = javascript_exceptions[pattern]
            setting_value = exception_data.get('setting')
            
            logger.info(f"✓ Found matching pattern: {found_pattern} with setting={setting_value}")
            break
    
    if site_found:
        criteria_met += 1
        feedback_parts.append(f"✓ JavaScript exception found for: {found_pattern}")
        
        # Check if pattern is reasonable
        if normalize_pattern(found_pattern) == normalize_pattern(target_site):
            criteria_met += 1
            feedback_parts.append(f"✓ Site pattern matches target: {target_site}")
        else:
            feedback_parts.append(f"⚠ Site pattern '{found_pattern}' differs from expected '{target_site}'")
            criteria_met += 0.5  # Partial credit
    else:
        feedback_parts.append(f"✗ JavaScript exception not found for '{target_site}' or any variant")
        feedback_parts.append(f"  Searched patterns: {', '.join(possible_patterns[:3])}")
        
        # Show what exceptions exist (if any)
        if javascript_exceptions:
            existing_sites = list(javascript_exceptions.keys())[:3]
            feedback_parts.append(f"  Found other sites: {', '.join(existing_sites)}")
    
    # Criterion 4: Permission value is BLOCK (2) not ALLOW (1)
    if setting_value is not None:
        if setting_value == 2:
            criteria_met += 1
            feedback_parts.append(f"✓ Block permission correctly set (setting=2)")
        elif setting_value == 1:
            feedback_parts.append(f"✗ Site is set to ALLOW (setting=1) instead of BLOCK (setting=2)")
        else:
            feedback_parts.append(f"⚠ Unexpected setting value: {setting_value} (expected 2 for BLOCK)")
            criteria_met += 0.3  # Small partial credit for having any setting
    else:
        if site_found:
            feedback_parts.append("✗ Setting value not found in exception data")
    
    # Criterion 5: Verify JavaScript not disabled globally
    default_js_setting = profile.get('default_content_setting_values', {}).get('javascript', 1)
    
    if default_js_setting == 1:  # 1 = ALLOW (default)
        criteria_met += 1
        feedback_parts.append("✓ JavaScript enabled globally (site-specific block only)")
    elif default_js_setting == 2:  # 2 = BLOCK
        feedback_parts.append("✗ JavaScript disabled globally (should be site-specific only)")
    else:
        feedback_parts.append(f"⚠ Unexpected default JavaScript setting: {default_js_setting}")
        criteria_met += 0.5  # Partial credit
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (75%)
    
    # Build final feedback
    feedback_parts.append("")
    feedback_parts.append("=" * 60)
    feedback_parts.append(f"Criteria met: {criteria_met:.1f}/{total_criteria}")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'✅ PASSED' if passed else '❌ FAILED'}")
    
    if not passed:
        feedback_parts.append("")
        feedback_parts.append("To complete this task:")
        feedback_parts.append("  1. Navigate to chrome://settings/content/javascript")
        feedback_parts.append("  2. Find 'Not allowed to use JavaScript' section")
        feedback_parts.append("  3. Click 'Add' button")
        feedback_parts.append(f"  4. Enter '{target_site}' in the site field")
        feedback_parts.append("  5. Click 'Add' to save")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "site_found": site_found,
            "found_pattern": found_pattern,
            "setting_value": setting_value,
            "default_javascript": default_js_setting,
            "javascript_exceptions_count": len(javascript_exceptions)
        }
    }


def generate_url_patterns(site: str) -> List[str]:
    """
    Generate possible URL patterns that Chrome might use for the given site.
    
    Chrome can store site patterns in various formats:
    - example.com
    - [*.]example.com
    - https://example.com:443
    - http://example.com:80
    
    Args:
        site: Base site domain (e.g., "example.com")
        
    Returns:
        List of possible pattern strings
    """
    patterns = [
        site,
        f"[*.]{site}",
        f"https://{site}:443",
        f"http://{site}:80",
        f"https://{site}",
        f"http://{site}",
        f"*://{site}/*",
        f"{site}:*"
    ]
    
    # Also try with www prefix
    if not site.startswith('www.'):
        patterns.extend([
            f"www.{site}",
            f"[*.]www.{site}"
        ])
    
    return patterns


def normalize_pattern(pattern: str) -> str:
    """
    Normalize URL pattern for comparison.
    
    Removes protocol, port, wildcards, and brackets for basic matching.
    
    Args:
        pattern: URL pattern string
        
    Returns:
        Normalized pattern string
    """
    # Remove common prefixes and brackets
    normalized = pattern.lower()
    normalized = re.sub(r'^https?://', '', normalized)
    normalized = re.sub(r':\d+$', '', normalized)  # Remove port
    normalized = normalized.replace('[*.]', '')
    normalized = normalized.replace('*', '')
    normalized = normalized.replace('/', '')
    normalized = normalized.strip()
    
    return normalized
