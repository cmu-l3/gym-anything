#!/usr/bin/env python3
"""
Verifier for Chrome Experimental Features Configuration Task (chrome_flags_config@1)
Task: Enable specific Chrome flags through chrome://flags interface

Verification Strategy:
- Copy Chrome's Local State file from container (located in Chrome config root, not Default profile)
- Parse JSON and extract browser.enabled_labs_experiments array
- Verify presence of three specific flag IDs:
  1. smooth-scrolling (Smooth Scrolling)
  2. enable-parallel-downloading (Parallel downloading)
  3. heavy-ad-intervention (Heavy Ad Intervention)
- Flags are stored with @<state> suffix, e.g., "smooth-scrolling@1" where @1 means enabled
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Expected flag IDs (internal names used in Local State)
EXPECTED_FLAGS = {
    "smooth-scrolling": "Smooth Scrolling",
    "enable-parallel-downloading": "Parallel downloading",
    "heavy-ad-intervention": "Heavy Ad Intervention"
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for chrome_flags_config@1.
    
    Verifies that all three experimental Chrome flags have been enabled:
    - Smooth Scrolling (smooth-scrolling)
    - Parallel downloading (enable-parallel-downloading)
    - Heavy Ad Intervention (heavy-ad-intervention)
    
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
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Extract Local State data
        local_state_data, error_msg = extract_local_state(copy_from_env)
        
        if local_state_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Local State file: {error_msg}"
            }
        
        # Verify flags configuration
        verification_result = verify_chrome_flags(local_state_data)
        
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


def extract_local_state(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Local State file from container and parse JSON.
    
    Local State is located at:
    - /home/ga/.config/google-chrome-cdp/Local State
    - OR /home/ga/.config/google-chrome/Local State
    
    Note: "Local State" has a space in the filename
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (local_state_data: dict or None, error_message: str)
    """
    temp_file = None
    try:
        # Create temporary file for Local State
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Local State file
        possible_paths = [
            "/tmp/local_state_export.json",  # From export script
            "/home/ga/.config/google-chrome-cdp/Local State",  # Primary location
            "/home/ga/.config/google-chrome/Local State",  # Alternative location
        ]
        
        local_state_data = None
        successful_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Attempting to copy Local State from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        local_state_data = json.load(f)
                    
                    successful_path = container_path
                    logger.info(f"✓ Successfully copied and parsed Local State from: {container_path}")
                    break
                else:
                    logger.debug(f"File at {container_path} is empty or doesn't exist")
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if local_state_data is None:
            error_msg = "Could not access Local State file from any known location"
            logger.error(error_msg)
            return None, error_msg
        
        return local_state_data, ""
        
    except json.JSONDecodeError as e:
        error_msg = f"Failed to parse Local State JSON: {e}"
        logger.error(error_msg)
        return None, error_msg
    except Exception as e:
        error_msg = f"Error extracting Local State: {e}"
        logger.error(error_msg)
        return None, error_msg
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def verify_chrome_flags(local_state_data: Dict) -> Dict[str, Any]:
    """
    Verify that the expected Chrome flags are enabled in Local State.
    
    Flags are stored in: browser.enabled_labs_experiments array
    Format: "flag-id@1" where @1 indicates enabled state
    
    Args:
        local_state_data: Parsed Local State JSON data
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    # Navigate to enabled_labs_experiments array
    browser_config = local_state_data.get('browser', {})
    enabled_experiments = browser_config.get('enabled_labs_experiments', [])
    
    logger.info(f"Found {len(enabled_experiments)} enabled experiments in Local State")
    
    # Extract flag IDs from experiments (remove @<state> suffix)
    enabled_flag_ids = set()
    for exp in enabled_experiments:
        # Experiments are stored as "flag-id@1" where @1 means enabled
        # Extract just the flag ID part before @
        if '@' in exp:
            flag_id = exp.split('@')[0]
        else:
            flag_id = exp
        enabled_flag_ids.add(flag_id)
    
    logger.info(f"Enabled flag IDs: {enabled_flag_ids}")
    
    # Check which expected flags are present
    expected_flag_ids = set(EXPECTED_FLAGS.keys())
    found_flags = expected_flag_ids.intersection(enabled_flag_ids)
    missing_flags = expected_flag_ids - found_flags
    
    # Log detailed results
    logger.info("=" * 60)
    logger.info("Flag verification results:")
    for flag_id, display_name in EXPECTED_FLAGS.items():
        status = "✓ ENABLED" if flag_id in found_flags else "✗ MISSING"
        logger.info(f"  {status} | {display_name} ({flag_id})")
    logger.info("=" * 60)
    
    # Calculate score based on number of flags enabled
    num_found = len(found_flags)
    total_expected = len(expected_flag_ids)
    score = int((num_found / total_expected) * 100)
    
    # Task requires ALL flags to be enabled for pass
    passed = (num_found == total_expected)
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"Chrome Experimental Flags Configuration: {num_found}/{total_expected} flags enabled")
    feedback_parts.append("")
    
    # List each flag's status
    for flag_id, display_name in EXPECTED_FLAGS.items():
        if flag_id in found_flags:
            feedback_parts.append(f"  ✓ {display_name} ({flag_id})")
        else:
            feedback_parts.append(f"  ✗ {display_name} ({flag_id}) - NOT ENABLED")
    
    feedback_parts.append("")
    
    if passed:
        feedback_parts.append("✅ Task completed successfully!")
        feedback_parts.append("All three experimental features have been enabled.")
    elif num_found > 0:
        feedback_parts.append(f"⚠ Partial completion: {num_found}/{total_expected} flags enabled")
        feedback_parts.append(f"Missing: {', '.join(EXPECTED_FLAGS[f] for f in missing_flags)}")
    else:
        feedback_parts.append("❌ Task not completed")
        feedback_parts.append("No experimental flags were enabled.")
        feedback_parts.append("Agent should navigate to chrome://flags and enable the required features.")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Final verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "expected_flags": list(expected_flag_ids),
            "found_flags": list(found_flags),
            "missing_flags": list(missing_flags),
            "num_found": num_found,
            "total_expected": total_expected,
            "all_enabled_experiments": list(enabled_flag_ids)
        }
    }
