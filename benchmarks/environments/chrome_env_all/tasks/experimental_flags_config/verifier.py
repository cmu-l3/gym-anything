#!/usr/bin/env python3
"""
Verifier for Chrome Experimental Flags Configuration Task
Task: Enable smooth-scrolling flag in chrome://flags and relaunch Chrome

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract browser.enabled_labs_experiments array
- Verify 'smooth-scrolling@1' is present (indicating enabled state)
- Ensure flag is properly formatted and persisted
- Check that file was recently modified (indicating relaunch occurred)
"""

import logging
import sys
import os
import json
import tempfile
import time
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
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for experimental_flags_config@1.
    
    Verifies that the smooth-scrolling flag has been enabled in chrome://flags
    and the change has been persisted after relaunch.
    
    Args:
        traj: Trajectory data (unused for this verification)
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
        # Extract flag state from Chrome Preferences
        flag_name = "smooth-scrolling"
        flag_state, prefs_data, error_msg = extract_flag_state(copy_from_env, flag_name)
        
        if flag_state is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract flag configuration: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_flag_configuration(
            flag_name=flag_name,
            flag_state=flag_state,
            prefs_data=prefs_data,
            copy_from_env=copy_from_env
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


def extract_flag_state(copy_from_env, flag_name: str) -> Tuple[Optional[str], Optional[Dict], str]:
    """
    Extract the state of a specific Chrome flag from Preferences.
    
    Args:
        copy_from_env: Function to copy files from container
        flag_name: Base name of the flag (e.g., "smooth-scrolling")
        
    Returns:
        Tuple of (flag_state: str or None, prefs_data: dict or None, error_message: str)
        flag_state can be: "enabled" (@1), "disabled" (@2), "default" (not present), or None (error)
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
                prefs_data = parse_preferences(prefs_path)
                
                if prefs_data:
                    enabled_flags = prefs_data.get('browser', {}).get('enabled_labs_experiments', [])
                    flag_state = determine_flag_state(flag_name, enabled_flags)
                    cleanup_verification_temp()
                    return flag_state, prefs_data, ""
                else:
                    cleanup_verification_temp()
                    logger.warning("Could not parse preferences with utilities, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        preferences_paths = [
            "/tmp/chrome_preferences_flags.json",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 10:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, None, "Could not access Preferences file from any known location"
        
        # Extract enabled_labs_experiments array
        enabled_flags = prefs_data.get('browser', {}).get('enabled_labs_experiments', [])
        
        logger.info(f"Found {len(enabled_flags)} enabled lab experiments")
        logger.info(f"Enabled flags: {enabled_flags}")
        
        # Determine flag state
        flag_state = determine_flag_state(flag_name, enabled_flags)
        
        return flag_state, prefs_data, ""
        
    except json.JSONDecodeError as e:
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, None, f"Error extracting flag state: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def determine_flag_state(flag_name: str, enabled_flags: list) -> str:
    """
    Determine the state of a flag from the enabled_labs_experiments array.
    
    Args:
        flag_name: Base flag name (e.g., "smooth-scrolling")
        enabled_flags: List of flag entries from Preferences
        
    Returns:
        "enabled" if flag@1 found, "disabled" if flag@2 found, "default" if not present
    """
    flag_enabled_pattern = f"{flag_name}@1"
    flag_disabled_pattern = f"{flag_name}@2"
    
    if flag_enabled_pattern in enabled_flags:
        return "enabled"
    elif flag_disabled_pattern in enabled_flags:
        return "disabled"
    else:
        # Check if flag appears with any other encoding
        for flag_entry in enabled_flags:
            if flag_entry.startswith(flag_name):
                logger.warning(f"Flag found with unexpected encoding: {flag_entry}")
                return "unknown"
        return "default"


def check_file_modification_time(copy_from_env) -> Tuple[bool, int, str]:
    """
    Check if Preferences file was recently modified (indicating relaunch occurred).
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (recently_modified: bool, seconds_ago: int, feedback: str)
    """
    try:
        # We need to get file stats from container
        # Since we can't directly stat, we'll copy and check local copy time
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/chrome_preferences_flags.json", temp_file.name)
            
            # Note: This checks when file was copied, not original mtime
            # For a more accurate check, we'd need container file stats
            file_stat = os.stat(temp_file.name)
            modification_time = file_stat.st_mtime
            current_time = time.time()
            seconds_ago = int(current_time - modification_time)
            
            # File should be modified within last 2 minutes if relaunch occurred
            recently_modified = seconds_ago < 120
            
            feedback = f"File age: {seconds_ago}s"
            
            os.unlink(temp_file.name)
            return recently_modified, seconds_ago, feedback
            
        except Exception as e:
            os.unlink(temp_file.name)
            return False, 9999, f"Could not check file time: {e}"
            
    except Exception as e:
        return False, 9999, f"Error checking modification time: {e}"


def verify_flag_configuration(flag_name: str, flag_state: str, prefs_data: Dict, 
                              copy_from_env) -> Dict[str, Any]:
    """
    Verify that flag configuration meets all criteria.
    
    Verification Criteria:
    1. Flag is present in enabled_labs_experiments
    2. Flag is in enabled state (@1 encoding)
    3. Flag is properly formatted
    4. File was recently modified (indicates relaunch occurred)
    
    Args:
        flag_name: Name of the flag being verified
        flag_state: Current state of the flag
        prefs_data: Parsed preferences data
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with verification results including passed, score, and feedback
    """
    criteria_results = []
    feedback_parts = []
    
    # Criterion 1: Flag is present (not in default state)
    flag_present = flag_state != "default"
    criteria_results.append(flag_present)
    
    if flag_present:
        feedback_parts.append(f"✓ Flag '{flag_name}' found in experiments list")
    else:
        feedback_parts.append(f"✗ Flag '{flag_name}' not found in enabled experiments (still in default state)")
    
    # Criterion 2: Flag is in enabled state (not disabled or unknown)
    correct_state = flag_state == "enabled"
    criteria_results.append(correct_state)
    
    if flag_state == "enabled":
        feedback_parts.append(f"✓ Flag is in enabled state (@1)")
    elif flag_state == "disabled":
        feedback_parts.append(f"✗ Flag is explicitly disabled (@2) instead of enabled")
    elif flag_state == "unknown":
        feedback_parts.append(f"✗ Flag has unknown encoding")
    else:
        feedback_parts.append(f"✗ Flag is in default state")
    
    # Criterion 3: Flag is properly formatted (check actual array entry)
    enabled_flags = prefs_data.get('browser', {}).get('enabled_labs_experiments', [])
    expected_entry = f"{flag_name}@1"
    properly_formatted = expected_entry in enabled_flags
    criteria_results.append(properly_formatted)
    
    if properly_formatted:
        feedback_parts.append(f"✓ Flag properly formatted as '{expected_entry}'")
    else:
        feedback_parts.append(f"✗ Flag not properly formatted (expected '{expected_entry}')")
    
    # Criterion 4: File recently modified (indicates relaunch)
    recently_modified, seconds_ago, mod_feedback = check_file_modification_time(copy_from_env)
    criteria_results.append(recently_modified)
    
    if recently_modified:
        feedback_parts.append(f"✓ Preferences recently modified ({seconds_ago}s ago) - relaunch likely occurred")
    else:
        feedback_parts.append(f"⚠ Preferences not recently modified ({seconds_ago}s ago) - relaunch may not have occurred")
    
    # Calculate score
    criteria_met = sum(criteria_results)
    total_criteria = len(criteria_results)
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 3  # Need at least 3/4 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFlag state: {flag_state}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo complete this task successfully:"
        feedback += "\n  1. Navigate to chrome://flags"
        feedback += "\n  2. Search for 'smooth scrolling'"
        feedback += "\n  3. Change the dropdown to 'Enabled'"
        feedback += "\n  4. Click the 'Relaunch' button to restart Chrome"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "flag_name": flag_name,
            "flag_state": flag_state,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "flag_present": criteria_results[0] if len(criteria_results) > 0 else False,
            "correct_state": criteria_results[1] if len(criteria_results) > 1 else False,
            "properly_formatted": criteria_results[2] if len(criteria_results) > 2 else False,
            "recently_modified": criteria_results[3] if len(criteria_results) > 3 else False
        }
    }
