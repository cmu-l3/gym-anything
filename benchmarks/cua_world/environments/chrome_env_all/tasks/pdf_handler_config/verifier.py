#!/usr/bin/env python3
"""
Verifier for Chrome PDF Handler Configuration Task (pdf_handler_config@1)
Task: Configure Chrome to download PDF files instead of opening them in built-in viewer

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to find 'plugins.always_open_pdf_externally' setting
- Verify the value is True (downloads PDFs) instead of default False (opens in Chrome)
- Validate setting structure and type correctness
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add Chrome utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
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
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for Chrome PDF handler configuration task.
    
    Verifies:
    1. Preferences file is accessible and valid
    2. PDF handler setting exists in Preferences
    3. Setting value is correct type (boolean)
    4. Setting is changed to True (download PDFs)
    
    Scoring:
    - 100%: All 4 criteria met (perfect configuration)
    - 75-99%: 3/4 criteria met (setting changed but minor issues)
    - 50-74%: 2/4 criteria met (setting found but not changed correctly)
    - 0-49%: <2 criteria met (task failed)
    
    Pass threshold: 75% (requires 3 out of 4 criteria)
    
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
        # Extract PDF handler setting from Preferences
        pdf_setting, prefs_data, error_msg = extract_pdf_handler_setting(copy_from_env)
        
        if pdf_setting is None and prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Preferences file: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_pdf_handler_configuration(pdf_setting, prefs_data)
        
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


def extract_pdf_handler_setting(copy_from_env):
    """
    Extract PDF handler setting from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (pdf_setting: bool or None, prefs_data: dict, error_message: str)
    """
    temp_file = None
    
    try:
        # Try using Chrome utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use Chrome verification utilities...")
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
                    plugins = prefs_data.get('plugins', {})
                    pdf_setting = plugins.get('always_open_pdf_externally', None)
                    logger.info(f"Successfully extracted PDF setting using utilities: {pdf_setting}")
                    return pdf_setting, prefs_data, ""
                else:
                    logger.warning("Preferences data is empty, trying fallback")
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction from multiple possible locations
        logger.info("Using fallback method to extract Preferences...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        preferences_paths = [
            "/tmp/chrome_prefs_export.json",  # Exported by post-task script
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
                else:
                    logger.debug(f"File empty or not found at: {container_path}")
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, None, "Could not access Preferences file from any known location"
        
        # Extract PDF handler setting
        plugins = prefs_data.get('plugins', {})
        pdf_setting = plugins.get('always_open_pdf_externally', None)
        
        logger.info(f"Extracted PDF handler setting: {pdf_setting} (type: {type(pdf_setting)})")
        return pdf_setting, prefs_data, ""
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        return None, None, f"Preferences file is not valid JSON: {e}"
    except Exception as e:
        logger.error(f"Error extracting PDF setting: {e}", exc_info=True)
        return None, None, f"Error extracting PDF setting: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception as e:
                logger.warning(f"Could not delete temp file: {e}")


def verify_pdf_handler_configuration(pdf_setting, prefs_data):
    """
    Verify that PDF handler was configured correctly.
    
    Checks:
    1. Preferences file is valid and accessible
    2. PDF handler setting exists in Preferences
    3. Setting value is correct type (boolean)
    4. Setting is True (download PDFs instead of opening)
    
    Args:
        pdf_setting: The extracted PDF handler setting value
        prefs_data: Full Preferences data dictionary
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: Preferences file valid
    if prefs_data:
        criteria_met += 1
        feedback_parts.append("✓ Preferences file is valid and accessible")
        logger.info("Criterion 1: PASS - Preferences file valid")
    else:
        feedback_parts.append("✗ Preferences file is invalid or empty")
        logger.info("Criterion 1: FAIL - Preferences file invalid")
    
    # Criterion 2: PDF handler setting exists
    if pdf_setting is not None:
        criteria_met += 1
        feedback_parts.append("✓ PDF handler setting found in Preferences")
        logger.info("Criterion 2: PASS - Setting found")
    else:
        feedback_parts.append("✗ PDF handler setting not found (plugins.always_open_pdf_externally)")
        feedback_parts.append("  Note: Setting may still be at default value (not explicitly set)")
        logger.info("Criterion 2: FAIL - Setting not found")
    
    # Criterion 3: Setting value is correct type (boolean)
    if isinstance(pdf_setting, bool):
        criteria_met += 1
        feedback_parts.append(f"✓ Setting value is correct type (boolean)")
        logger.info("Criterion 3: PASS - Correct type")
    else:
        feedback_parts.append(f"✗ Setting value has wrong type: {type(pdf_setting).__name__} (expected bool)")
        logger.info(f"Criterion 3: FAIL - Wrong type: {type(pdf_setting)}")
    
    # Criterion 4: Setting is True (download PDFs)
    if pdf_setting is True:
        criteria_met += 1
        feedback_parts.append("✓ PDF handler correctly set to DOWNLOAD mode")
        feedback_parts.append("  PDFs will now download instead of opening in Chrome")
        logger.info("Criterion 4: PASS - Setting is True (download mode)")
    elif pdf_setting is False:
        feedback_parts.append("✗ PDF handler is set to OPEN IN CHROME mode (expected DOWNLOAD mode)")
        feedback_parts.append("  Setting appears unchanged from default")
        logger.info("Criterion 4: FAIL - Setting is False (open mode)")
    elif pdf_setting is None:
        feedback_parts.append("✗ PDF handler setting not found or not set")
        feedback_parts.append("  Default behavior is to open PDFs in Chrome")
        logger.info("Criterion 4: FAIL - Setting is None (not set)")
    else:
        feedback_parts.append(f"✗ PDF handler has unexpected value: {pdf_setting}")
        logger.info(f"Criterion 4: FAIL - Unexpected value: {pdf_setting}")
    
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
        feedback += "\n\n💡 To complete this task:"
        feedback += "\n  1. Navigate to chrome://settings"
        feedback += "\n  2. Go to 'Privacy and security' → 'Site Settings'"
        feedback += "\n  3. Find 'PDF documents' in the content settings"
        feedback += "\n  4. Toggle ON: 'Download PDF files instead of opening in Chrome'"
    
    logger.info(f"Final verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "pdf_setting": pdf_setting,
            "criteria_met": criteria_met,
            "setting_exists": pdf_setting is not None,
            "correct_type": isinstance(pdf_setting, bool),
            "download_enabled": pdf_setting is True
        }
    }
