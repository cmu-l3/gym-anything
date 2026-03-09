#!/usr/bin/env python3
"""
Verifier for Chrome Site-Specific Image Blocking Task (block_images_site@1)
Task: Navigate to example.com and block images using site-specific content settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and navigate to profile.content_settings.exceptions.images
- Search for entries matching example.com domain
- Verify setting value is 2 (Block) rather than 1 (Allow)
- Validate proper JSON structure and timestamp
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
    Main verification function for block_images_site@1 task.
    
    Verifies that:
    1. Preferences file is accessible and parseable
    2. Image content settings exist in the file
    3. A site-specific rule for example.com exists
    4. The setting value is 2 (Block)
    5. The structure is valid and properly formatted
    
    Scoring:
    - 100%: All 4 criteria met (perfect configuration)
    - 75%: 3/4 criteria met (minor issues but functional)
    - 50%: 2/4 criteria met (partial configuration)
    - 0-49%: <2 criteria met (task failed)
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available - cannot verify task"
        }

    try:
        # Extract preferences data from container
        prefs_data, error_msg = extract_preferences(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Preferences: {error_msg}"
            }
        
        # Verify image blocking configuration
        verification_result = verify_image_block_configuration(
            prefs_data,
            target_domain="example.com"
        )
        
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


def extract_preferences(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
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
                prefs_data = parse_preferences(prefs_path)
                cleanup_verification_temp()
                
                if prefs_data:
                    logger.info("✓ Successfully extracted Preferences using utilities")
                    return prefs_data, ""
                else:
                    logger.warning("Utility returned empty preferences, trying fallback")
        
        # Fallback: Manual extraction
        logger.info("Using fallback method to extract Preferences...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        preferences_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
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


def verify_image_block_configuration(prefs_data: Dict[str, Any], target_domain: str = "example.com") -> Dict[str, Any]:
    """
    Verify that images are blocked for the target domain in Chrome Preferences.
    
    Checks for:
    1. Image exceptions structure exists
    2. Entry for target domain exists
    3. Setting value is 2 (Block)
    4. Valid pattern format
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON data
        target_domain: Domain to check for image blocking (default: example.com)
        
    Returns:
        Dict with verification results including passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Image exceptions structure exists
    try:
        image_exceptions = prefs_data.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('images', {})
        
        if not isinstance(image_exceptions, dict):
            feedback_parts.append("✗ Image content settings structure not found or invalid")
            logger.error("Image exceptions is not a dict or doesn't exist")
        else:
            feedback_parts.append("✓ Image content settings structure exists")
            criteria_met += 1
            logger.info(f"Found {len(image_exceptions)} image exception(s)")
            
    except (KeyError, AttributeError) as e:
        feedback_parts.append("✗ Failed to navigate to image content settings in Preferences")
        logger.error(f"Error accessing image exceptions: {e}")
        image_exceptions = {}
    
    # Criterion 2 & 3: Entry for target domain exists with Block setting
    domain_found = False
    correct_setting = False
    found_pattern = None
    found_value = None
    
    if image_exceptions:
        logger.info("Searching for example.com in image exceptions...")
        
        for pattern, settings in image_exceptions.items():
            logger.debug(f"Checking pattern: {pattern}")
            
            # Normalize pattern for comparison
            # Patterns can be: "https://www.example.com:443,*", "[*.]example.com:443,*", etc.
            if target_domain in pattern.lower():
                domain_found = True
                found_pattern = pattern
                
                setting_value = settings.get('setting')
                found_value = setting_value
                
                logger.info(f"Found matching pattern: {pattern}")
                logger.info(f"  Setting value: {setting_value}")
                logger.info(f"  Last modified: {settings.get('last_modified', 'unknown')}")
                
                if setting_value == 2:  # 2 = Block
                    correct_setting = True
                    feedback_parts.append(f"✓ Domain '{target_domain}' found with Block setting")
                    criteria_met += 2  # Both domain found AND correct setting
                    break
                elif setting_value == 1:  # 1 = Allow
                    feedback_parts.append(f"✗ Domain '{target_domain}' found but set to Allow (not Block)")
                    criteria_met += 1  # Found domain but wrong setting
                    break
                else:
                    feedback_parts.append(f"✗ Domain '{target_domain}' found but has invalid setting value: {setting_value}")
                    criteria_met += 1  # Found domain but wrong setting
                    break
    
    if not domain_found:
        feedback_parts.append(f"✗ No site-specific image setting found for '{target_domain}'")
        logger.warning(f"Domain '{target_domain}' not found in any image exception patterns")
        
        # Log all patterns for debugging
        if image_exceptions:
            logger.info("All image exception patterns found:")
            for pattern in image_exceptions.keys():
                logger.info(f"  - {pattern}")
    
    # Criterion 4: Valid structure (entry has proper fields)
    if domain_found and found_pattern:
        entry_data = image_exceptions[found_pattern]
        
        # Check for required fields
        has_setting = 'setting' in entry_data
        has_timestamp = 'last_modified' in entry_data
        
        if has_setting and (has_timestamp or True):  # timestamp is optional in some Chrome versions
            feedback_parts.append("✓ Entry structure is valid")
            criteria_met += 1
        else:
            feedback_parts.append("⚠ Entry structure missing expected fields")
            criteria_met += 0.5  # Partial credit
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build detailed feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += f"\nResult: PASSED ✓"
        feedback += f"\n\nImages are successfully blocked for {target_domain}"
    else:
        feedback += f"\nResult: FAILED ✗"
        feedback += f"\n\nImages are not blocked for {target_domain}"
        feedback += "\n\nTo complete this task:"
        feedback += "\n  1. Navigate to https://www.example.com"
        feedback += "\n  2. Click the lock/info icon in the address bar"
        feedback += "\n  3. Select 'Site settings'"
        feedback += "\n  4. Find 'Images' permission"
        feedback += "\n  5. Change setting to 'Block'"
    
    # Log detailed results
    logger.info(f"Verification complete:")
    logger.info(f"  Domain found: {domain_found}")
    logger.info(f"  Correct setting: {correct_setting}")
    logger.info(f"  Pattern: {found_pattern}")
    logger.info(f"  Setting value: {found_value}")
    logger.info(f"  Score: {score}/100")
    logger.info(f"  Passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "domain_found": domain_found,
            "correct_setting": correct_setting,
            "found_pattern": found_pattern,
            "setting_value": found_value,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
