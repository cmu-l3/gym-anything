#!/usr/bin/env python3
"""
Verifier for Chrome Custom Downloads Location Task (downloads_location_custom@1)
Task: Configure Chrome to use custom download location and verify with test download

Verification Strategy:
1. Check Chrome Preferences for download.default_directory setting
2. Verify CustomDownloads directory was created
3. Verify test file was downloaded to custom location
4. Ensure file is not in default Downloads location (optional strictness)

Scoring:
- 100%: All criteria met (preferences + directory + file in correct location)
- 75-99%: Preferences updated + directory exists, minor issues
- 50-74%: Partial success (configuration but no execution)
- 0-49%: Configuration not updated or task failed
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
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


def verify_task(traj, env_info, task_info):
    """
    Main verification function for downloads_location_custom@1 task.
    
    Verifies:
    1. Chrome Preferences has download.default_directory = /home/ga/CustomDownloads
    2. CustomDownloads directory exists
    3. test_download.pdf exists in CustomDownloads with size > 0
    4. (Optional) test_download.pdf NOT in default Downloads folder
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    # Expected values
    custom_path = "/home/ga/CustomDownloads"
    test_filename = "test_download.pdf"
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    try:
        # Criterion 1: Check Preferences file for download.default_directory
        logger.info("Checking Chrome Preferences for download location...")
        prefs_ok, download_dir = check_preferences_download_location(copy_from_env, custom_path)
        
        if prefs_ok:
            feedback_parts.append(f"✓ Preferences updated: download location set to {custom_path}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Preferences incorrect: download location is '{download_dir}' (expected '{custom_path}')")
        
        # Criterion 2: Check if CustomDownloads directory exists
        logger.info("Checking if CustomDownloads directory exists...")
        dir_exists = check_directory_exists(copy_from_env, custom_path)
        
        if dir_exists:
            feedback_parts.append(f"✓ CustomDownloads directory exists")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ CustomDownloads directory does NOT exist")
        
        # Criterion 3: Check if test file was downloaded to custom location
        logger.info("Checking if test file exists in custom location...")
        file_exists, file_size = check_file_downloaded(copy_from_env, custom_path, test_filename)
        
        if file_exists and file_size > 0:
            feedback_parts.append(f"✓ Test file downloaded to custom location ({file_size} bytes)")
            criteria_met += 1
        elif file_exists:
            feedback_parts.append(f"✗ Test file exists but is empty (0 bytes)")
        else:
            feedback_parts.append(f"✗ Test file NOT found in {custom_path}")
        
        # Criterion 4: Verify file NOT in default location (optional/bonus)
        logger.info("Checking that file is NOT in default Downloads...")
        not_in_default = check_file_not_in_default(copy_from_env, test_filename)
        
        if not_in_default:
            feedback_parts.append(f"✓ Test file correctly NOT in default Downloads folder")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ Test file also found in default Downloads (should only be in CustomDownloads)")
            # Still give partial credit since main goal is achieved
            criteria_met += 0.5
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'✅ PASSED' if passed else '❌ FAILED'}"
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "preferences_updated": prefs_ok,
                "directory_created": dir_exists,
                "file_downloaded": file_exists,
                "not_in_default": not_in_default,
                "configured_path": download_dir,
                "file_size": file_size if file_exists else 0
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


def check_preferences_download_location(copy_from_env, expected_path):
    """
    Check Chrome Preferences for download.default_directory setting.
    
    Returns:
        Tuple of (matches_expected: bool, actual_path: str)
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
                prefs = parse_preferences(files["Preferences"])
                download_config = prefs.get('download', {})
                default_dir = download_config.get('default_directory', '')
                cleanup_verification_temp()
                
                # Normalize paths for comparison (handle trailing slashes)
                expected_normalized = expected_path.rstrip('/')
                actual_normalized = default_dir.rstrip('/')
                
                matches = (actual_normalized == expected_normalized)
                return matches, default_dir
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_locations = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for prefs_path in prefs_locations:
            try:
                copy_from_env(prefs_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    break
            except Exception as e:
                logger.debug(f"Could not copy from {prefs_path}: {e}")
                continue
        
        if not prefs_data:
            return False, "Preferences file not found"
        
        # Extract download directory
        download_config = prefs_data.get('download', {})
        default_dir = download_config.get('default_directory', '')
        
        expected_normalized = expected_path.rstrip('/')
        actual_normalized = default_dir.rstrip('/')
        
        matches = (actual_normalized == expected_normalized)
        return matches, default_dir
        
    except Exception as e:
        logger.error(f"Error checking preferences: {e}")
        return False, f"Error: {str(e)}"
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def check_directory_exists(copy_from_env, directory_path):
    """
    Check if CustomDownloads directory exists in container.
    
    Returns:
        bool: True if directory exists
    """
    # Strategy: Try to list directory or copy a test file from it
    # If we can successfully interact with it, it exists
    
    try:
        # Try to copy a file that might be in the directory
        # If directory doesn't exist, this will fail
        temp_file = tempfile.NamedTemporaryFile(delete=False)
        temp_file.close()
        
        # Attempt to copy test file from custom directory
        test_file_path = f"{directory_path}/test_download.pdf"
        try:
            copy_from_env(test_file_path, temp_file.name)
            # If successful, directory exists (and file is in it)
            os.unlink(temp_file.name)
            return True
        except Exception as e:
            # File might not exist, but directory could still exist
            # Try checking via summary file
            os.unlink(temp_file.name)
            
            # Check summary JSON for directory existence info
            summary_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            summary_file.close()
            
            try:
                copy_from_env("/tmp/download_task_summary.json", summary_file.name)
                with open(summary_file.name, 'r') as f:
                    summary = json.load(f)
                dir_exists = summary.get('custom_dir_exists', False)
                os.unlink(summary_file.name)
                return dir_exists
            except:
                os.unlink(summary_file.name)
                # Cannot determine, assume directory doesn't exist
                return False
                
    except Exception as e:
        logger.error(f"Error checking directory existence: {e}")
        return False


def check_file_downloaded(copy_from_env, directory_path, filename):
    """
    Check if test file was downloaded to custom location.
    
    Returns:
        Tuple of (exists: bool, size: int)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_file.close()
        
        file_path = f"{directory_path}/{filename}"
        
        try:
            copy_from_env(file_path, temp_file.name)
            
            # Check if file has content
            if os.path.exists(temp_file.name):
                file_size = os.path.getsize(temp_file.name)
                os.unlink(temp_file.name)
                
                if file_size > 0:
                    logger.info(f"✓ Test file found with size {file_size} bytes")
                    return True, file_size
                else:
                    logger.warning("Test file found but is empty")
                    return True, 0
            else:
                os.unlink(temp_file.name)
                return False, 0
                
        except Exception as e:
            logger.debug(f"Could not copy test file from {file_path}: {e}")
            os.unlink(temp_file.name)
            return False, 0
            
    except Exception as e:
        logger.error(f"Error checking file download: {e}")
        return False, 0


def check_file_not_in_default(copy_from_env, filename):
    """
    Check that file is NOT in default Downloads location.
    
    Returns:
        bool: True if file is NOT in default location (as desired)
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_file.close()
        
        default_path = f"/home/ga/Downloads/{filename}"
        
        try:
            copy_from_env(default_path, temp_file.name)
            
            # If we successfully copied, file exists in default location (BAD)
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                logger.warning("Test file found in default Downloads folder")
                os.unlink(temp_file.name)
                return False  # File IS in default (not desired)
            else:
                os.unlink(temp_file.name)
                return True  # File NOT in default (good)
                
        except Exception as e:
            # Could not copy = file doesn't exist in default location (GOOD)
            os.unlink(temp_file.name)
            logger.info("Test file correctly NOT in default Downloads")
            return True
            
    except Exception as e:
        logger.error(f"Error checking default location: {e}")
        # Assume file is not there if we can't check
        return True
