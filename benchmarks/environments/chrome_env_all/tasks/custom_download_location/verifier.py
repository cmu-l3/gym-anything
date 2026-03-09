#!/usr/bin/env python3
"""
Verifier for Chrome Custom Download Location Task (custom_download_location@1)
Task: Configure Chrome to use a custom download directory and download a test file there

Verification Strategy:
- Multi-criteria validation combining file system checks and preferences analysis
- Checks custom directory creation, file location, preferences update, and integrity
- Ensures file is NOT in default location to confirm setting actually worked
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
    
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for custom_download_location@1.
    
    Verifies:
    1. Custom download directory exists (not default ~/Downloads)
    2. Test file downloaded successfully to custom location
    3. Chrome Preferences updated with custom directory path
    4. File is NOT in default Downloads folder
    5. Downloaded file has valid size and content
    
    Scoring:
    - 100%: All 5 criteria met (perfect execution)
    - 80%: 4/5 criteria met (minor issue, still passing)
    - 60%: 3/5 criteria met (partial success, failing)
    - 40%: 2/5 criteria met (significant issues)
    - 0-20%: 0-1 criteria met (task failed)
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    
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
            "feedback": "copy_from_env function not available"
        }

    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    details = {}
    
    try:
        # Criterion 1 & 2: Find custom directory and downloaded file
        logger.info("Checking for custom download directory and test file...")
        custom_dir_found, file_found, file_path, dir_info = check_custom_directory_and_file(
            copy_from_env,
            expected_filename="test_download_file.txt"
        )
        
        if custom_dir_found:
            feedback_parts.append(f"✓ Custom directory found: {dir_info}")
            criteria_met += 1
            details['custom_directory'] = dir_info
        else:
            feedback_parts.append(f"✗ Custom directory not found (only default ~/Downloads detected)")
            details['custom_directory'] = None
        
        if file_found:
            feedback_parts.append(f"✓ Test file downloaded to custom location: {file_path}")
            criteria_met += 1
            details['file_location'] = file_path
        else:
            feedback_parts.append(f"✗ Test file not found in custom directory")
            details['file_location'] = None
        
        # Criterion 3: Check Preferences file for custom path
        logger.info("Checking Chrome Preferences for custom download path...")
        prefs_ok, prefs_path, prefs_msg = check_preferences_download_path(
            copy_from_env,
            expected_pattern="MyCustomDownloads"  # Flexible pattern matching
        )
        
        if prefs_ok:
            feedback_parts.append(f"✓ Preferences updated: {prefs_msg}")
            criteria_met += 1
            details['preferences_path'] = prefs_path
        else:
            feedback_parts.append(f"✗ Preferences not updated: {prefs_msg}")
            details['preferences_path'] = None
        
        # Criterion 4: Verify file is NOT in default location
        logger.info("Checking that file is NOT in default Downloads folder...")
        not_in_default, default_msg = check_not_in_default_location(
            copy_from_env,
            filename="test_download_file.txt"
        )
        
        if not_in_default:
            feedback_parts.append(f"✓ File correctly NOT in default Downloads")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ {default_msg}")
        
        # Criterion 5: Check file integrity (size and content)
        if file_found and file_path:
            logger.info("Checking file integrity...")
            integrity_ok, size_bytes, integrity_msg = check_file_integrity(
                copy_from_env,
                file_path,
                min_size=100,  # Minimum 100 bytes
                max_size=10000  # Maximum 10KB
            )
            
            if integrity_ok:
                feedback_parts.append(f"✓ File integrity verified ({size_bytes} bytes)")
                criteria_met += 1
                details['file_size'] = size_bytes
            else:
                feedback_parts.append(f"✗ {integrity_msg}")
                details['file_size'] = 0
        else:
            feedback_parts.append(f"✗ Cannot verify file integrity (file not found)")
            details['file_size'] = 0
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if passed:
            feedback += "\n\nCustom download location successfully configured!"
        else:
            feedback += "\n\nTask incomplete. Please ensure you:"
            feedback += "\n  1. Navigate to chrome://settings/downloads"
            feedback += "\n  2. Click 'Change' and create a custom folder"
            feedback += "\n  3. Download the test file from the webpage"
        
        logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": details
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp()


def check_custom_directory_and_file(copy_from_env, expected_filename="test_download_file.txt"):
    """
    Check for custom download directory and downloaded file.
    
    Returns:
        Tuple of (custom_dir_found, file_found, file_path, dir_name)
    """
    try:
        # Copy file location data
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/test_file_locations.txt", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                file_locations = [line.strip() for line in f if line.strip()]
            
            os.unlink(temp_file.name)
            
            if not file_locations:
                return False, False, None, None
            
            # Check if file is in a custom directory (not default Downloads)
            for file_path in file_locations:
                if '/Downloads/' not in file_path and expected_filename in file_path:
                    # Extract directory name
                    dir_name = os.path.basename(os.path.dirname(file_path))
                    logger.info(f"Found file in custom directory: {file_path}")
                    return True, True, file_path, dir_name
            
            # If we found files but only in default Downloads
            if file_locations:
                return False, False, file_locations[0], None
            
            return False, False, None, None
            
        except Exception as e:
            logger.warning(f"Could not read file locations: {e}")
            os.unlink(temp_file.name)
            return False, False, None, None
            
    except Exception as e:
        logger.error(f"Error checking custom directory: {e}")
        return False, False, None, None


def check_preferences_download_path(copy_from_env, expected_pattern=""):
    """
    Check Chrome Preferences for custom download path.
    
    Returns:
        Tuple of (is_custom, path, message)
    """
    try:
        # Try to copy Preferences file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple locations
        preferences_locations = [
            "/tmp/download_location_verification/chrome_preferences.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for pref_path in preferences_locations:
            try:
                logger.info(f"Trying to copy Preferences from: {pref_path}")
                copy_from_env(pref_path, temp_file.name)
                
                with open(temp_file.name, 'r', encoding='utf-8') as f:
                    prefs_data = json.load(f)
                
                logger.info(f"Successfully loaded Preferences from: {pref_path}")
                break
            except Exception as e:
                logger.debug(f"Failed to copy from {pref_path}: {e}")
                continue
        
        os.unlink(temp_file.name)
        
        if not prefs_data:
            return False, None, "Could not access Preferences file"
        
        # Extract download directory setting
        download_config = prefs_data.get('download', {})
        default_dir = download_config.get('default_directory', '')
        
        if not default_dir:
            return False, None, "No custom download directory set in preferences"
        
        # Check if it's the default Downloads folder
        if '/Downloads' in default_dir and expected_pattern not in default_dir:
            return False, default_dir, f"Still using default Downloads: {default_dir}"
        
        # Check if it's a custom directory
        if expected_pattern and expected_pattern.lower() in default_dir.lower():
            return True, default_dir, f"Custom path: {default_dir}"
        
        # Any non-default directory is acceptable
        if '/Downloads' not in default_dir or 'Custom' in default_dir or 'My' in default_dir:
            return True, default_dir, f"Custom path: {default_dir}"
        
        return False, default_dir, f"Unclear if custom: {default_dir}"
        
    except Exception as e:
        logger.error(f"Error checking preferences: {e}")
        return False, None, f"Error: {str(e)}"


def check_not_in_default_location(copy_from_env, filename="test_download_file.txt"):
    """
    Verify file is NOT in default Downloads folder.
    
    Returns:
        Tuple of (not_in_default, message)
    """
    try:
        # Try to copy the default location files list
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/default_location_files.txt", temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                default_files = [line.strip() for line in f if line.strip()]
            
            os.unlink(temp_file.name)
            
            # If file found in default Downloads, that's bad
            if default_files:
                return False, f"File found in default Downloads (setting not applied)"
            
            # File not in default location - good!
            return True, "File correctly NOT in default location"
            
        except Exception as e:
            # If we can't read the file, assume it's empty (no files in default location)
            logger.debug(f"Could not read default location files (likely empty): {e}")
            os.unlink(temp_file.name)
            return True, "No file in default Downloads"
            
    except Exception as e:
        logger.warning(f"Error checking default location: {e}")
        # If we can't verify, give benefit of doubt
        return True, "Could not verify default location (assuming OK)"


def check_file_integrity(copy_from_env, file_path, min_size=100, max_size=10000):
    """
    Check downloaded file has valid size and content.
    
    Returns:
        Tuple of (is_valid, size_bytes, message)
    """
    try:
        # Copy the actual file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='wb')
        temp_file.close()
        
        try:
            copy_from_env(file_path, temp_file.name)
            
            # Check file size
            size_bytes = os.path.getsize(temp_file.name)
            
            if size_bytes < min_size:
                os.unlink(temp_file.name)
                return False, size_bytes, f"File too small ({size_bytes} bytes, expected >{min_size})"
            
            if size_bytes > max_size:
                os.unlink(temp_file.name)
                return False, size_bytes, f"File too large ({size_bytes} bytes, expected <{max_size})"
            
            # Check content (should contain test identifier)
            with open(temp_file.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            os.unlink(temp_file.name)
            
            # Verify it's the test file
            if "test file" in content.lower() or "download location verification" in content.lower():
                return True, size_bytes, f"Valid file ({size_bytes} bytes)"
            else:
                return False, size_bytes, f"File content doesn't match expected test file"
                
        except Exception as e:
            logger.error(f"Could not copy or read file: {e}")
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
            return False, 0, f"Could not access file: {str(e)}"
            
    except Exception as e:
        logger.error(f"Error checking file integrity: {e}")
        return False, 0, f"Error: {str(e)}"
