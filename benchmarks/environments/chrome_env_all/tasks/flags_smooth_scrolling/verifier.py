#!/usr/bin/env python3
"""
Verifier for Chrome Experimental Flags Configuration Task (flags_smooth_scrolling@1)
Task: Navigate to chrome://flags, enable smooth scrolling flag, and relaunch Chrome

Verification Strategy:
- Copy Local State file from container (Chrome's global configuration)
- Parse JSON and extract browser.enabled_labs_experiments array
- Check for smooth-scrolling flag in various possible formats
- Implement retry logic to handle Chrome relaunch timing
- Validate flag is properly enabled and persisted
"""

import logging
import sys
import os
import json
import time
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for flags_smooth_scrolling@1.
    
    Verifies that the smooth scrolling experimental flag was enabled in chrome://flags
    and that the configuration persisted after Chrome relaunch.
    
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
            "feedback": "Copy function not available in environment - cannot verify task"
        }

    try:
        # Get Local State data with retry logic for relaunch timing
        local_state_data, error_msg = extract_local_state_with_retry(
            copy_from_env, 
            max_retries=3, 
            delay=2
        )
        
        if local_state_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to retrieve Local State configuration: {error_msg}"
            }
        
        # Verify smooth scrolling flag is enabled
        verification_result = verify_smooth_scrolling_flag(local_state_data)
        
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


def extract_local_state_with_retry(copy_from_env, max_retries=3, delay=2) -> Tuple[Optional[Dict], str]:
    """
    Extract Local State file from container with retry logic.
    
    Chrome may still be relaunching when verification starts, so we implement
    retry logic with delays to handle timing issues.
    
    Args:
        copy_from_env: Function to copy files from container
        max_retries: Maximum number of retry attempts
        delay: Delay in seconds between retries
        
    Returns:
        Tuple of (local_state_data: dict or None, error_message: str)
    """
    for attempt in range(max_retries):
        logger.info(f"Attempting to retrieve Local State (attempt {attempt + 1}/{max_retries})...")
        
        local_state_data, error = extract_local_state(copy_from_env)
        
        if local_state_data is not None:
            logger.info(f"✓ Successfully retrieved Local State on attempt {attempt + 1}")
            return local_state_data, ""
        
        # If not the last attempt, wait before retrying
        if attempt < max_retries - 1:
            logger.warning(f"Attempt {attempt + 1} failed: {error}. Retrying in {delay}s...")
            time.sleep(delay)
        else:
            logger.error(f"All {max_retries} attempts failed")
            return None, f"Failed after {max_retries} attempts: {error}"
    
    return None, "Unexpected error in retry logic"


def extract_local_state(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract and parse Local State file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_state_data: dict or None, error_message: str)
    """
    temp_file = None
    try:
        # Create temporary file for Local State
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Local State
        local_state_paths = [
            "/tmp/chrome_local_state.json",  # Exported by post-task script
            "/home/ga/.config/google-chrome-cdp/Local State",  # Primary location
            "/home/ga/.config/google-chrome/Local State",  # Alternative location
        ]
        
        local_state_data = None
        source_path = None
        
        for container_path in local_state_paths:
            try:
                logger.info(f"Trying to copy Local State from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Verify file was copied and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        local_state_data = json.load(f)
                    
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed Local State from: {container_path}")
                    break
                else:
                    logger.debug(f"File at {temp_path} is empty or doesn't exist")
                    
            except json.JSONDecodeError as e:
                logger.warning(f"Failed to parse JSON from {container_path}: {e}")
                continue
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if local_state_data is None:
            return None, "Could not access or parse Local State from any known location"
        
        return local_state_data, ""
        
    except Exception as e:
        return None, f"Error extracting Local State: {str(e)}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_smooth_scrolling_flag(local_state_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that smooth scrolling flag is enabled in Local State.
    
    Checks:
    1. Local State has browser.enabled_labs_experiments array
    2. Array contains smooth-scrolling flag (trying multiple format variants)
    3. Flag is not in disabled experiments list
    4. Configuration structure is valid
    
    Args:
        local_state_data: Parsed Local State JSON data
        
    Returns:
        Verification result dict with passed, score, and detailed feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Local State has valid browser configuration
    browser_config = local_state_data.get('browser', {})
    has_browser_config = bool(browser_config)
    
    if has_browser_config:
        feedback_parts.append("✓ Browser configuration found in Local State")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Browser configuration not found in Local State")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts) + "\n\nLocal State file may be corrupted or invalid"
        }
    
    # Criterion 2: enabled_labs_experiments array exists
    enabled_experiments = browser_config.get('enabled_labs_experiments', None)
    has_experiments_array = enabled_experiments is not None
    
    if has_experiments_array:
        feedback_parts.append(f"✓ Enabled experiments array found ({len(enabled_experiments)} flag(s) enabled)")
        criteria_met += 1
    else:
        feedback_parts.append("✗ No enabled_labs_experiments array found")
        feedback_parts.append("  This suggests the agent did not enable any flags")
        
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": "\n".join(feedback_parts),
            "details": {
                "enabled_experiments": [],
                "smooth_scrolling_found": False
            }
        }
    
    # Criterion 3: Smooth scrolling flag is present
    # Try multiple possible flag identifier formats
    possible_flag_ids = [
        "smooth-scrolling",
        "smooth-scrolling@1",
        "smooth-scrolling@2",
        "smooth-scrolling@3",
        "enable-smooth-scrolling",
    ]
    
    smooth_scrolling_found = False
    found_flag_id = None
    
    for flag_id in possible_flag_ids:
        if flag_id in enabled_experiments:
            smooth_scrolling_found = True
            found_flag_id = flag_id
            break
    
    if smooth_scrolling_found:
        feedback_parts.append(f"✓ Smooth scrolling flag found: '{found_flag_id}'")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Smooth scrolling flag not found in enabled experiments")
        feedback_parts.append(f"  Current enabled flags: {enabled_experiments}")
        feedback_parts.append("  Expected flag IDs: " + ", ".join(possible_flag_ids[:3]))
    
    # Criterion 4: Flag is not in disabled list (if such list exists)
    disabled_experiments = browser_config.get('disabled_labs_experiments', [])
    not_disabled = found_flag_id not in disabled_experiments if found_flag_id else True
    
    if not_disabled and smooth_scrolling_found:
        feedback_parts.append("✓ Flag is not in disabled experiments list")
        criteria_met += 1
    elif not smooth_scrolling_found:
        # Can't check this if flag wasn't found
        feedback_parts.append("⚠ Could not verify disabled status (flag not found)")
    else:
        feedback_parts.append("✗ Flag found in disabled experiments list")
    
    # Criterion 5: Configuration structure is complete and valid
    structure_valid = (
        isinstance(enabled_experiments, list) and
        all(isinstance(flag, str) for flag in enabled_experiments) and
        len(enabled_experiments) > 0
    )
    
    if structure_valid:
        feedback_parts.append("✓ Configuration structure is valid")
        criteria_met += 1
    else:
        feedback_parts.append("✗ Configuration structure is invalid or malformed")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (75%)
    
    # Generate final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    
    if passed:
        feedback += f"\n✅ Task completed successfully!"
        feedback += f"\nSmooth scrolling experimental flag is now enabled."
    else:
        feedback += f"\n❌ Task incomplete or failed"
        if not smooth_scrolling_found:
            feedback += "\n\nThe smooth scrolling flag was not enabled in chrome://flags."
            feedback += "\nAgent should have:"
            feedback += "\n  1. Navigated to chrome://flags"
            feedback += "\n  2. Searched for 'smooth scrolling'"
            feedback += "\n  3. Changed dropdown to 'Enabled'"
            feedback += "\n  4. Clicked 'Relaunch' button"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "enabled_experiments": enabled_experiments if has_experiments_array else [],
            "smooth_scrolling_found": smooth_scrolling_found,
            "found_flag_id": found_flag_id,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
