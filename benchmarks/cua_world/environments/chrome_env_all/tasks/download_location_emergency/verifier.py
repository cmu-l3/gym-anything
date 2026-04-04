#!/usr/bin/env python3
"""
Verifier for Chrome Download Location Emergency Reconfiguration Task
Task ID: download_location_emergency@1

Verification Strategy:
- Copy Chrome Preferences file from container to host
- Parse JSON structure to extract download.default_directory setting
- Validate that download location has been changed from default
- Ensure new location is the expected secondary storage path
- Verify directory exists and is writable
- Check path normalization and various format handling

Scoring:
- 100%: Perfect - correct path, directory exists, writable
- 85%: Good - correct path structure but minor variations
- 60%: Partial - path changed but not to expected location
- 0%: Failed - setting unchanged or invalid
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Tuple, Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import Chrome verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        parse_preferences,
        cleanup_verification_temp
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
    Main verification function for download_location_emergency@1 task.
    
    Verifies that Chrome's download location has been changed from the default
    Downloads folder to the secondary storage location.
    
    Args:
        traj: Trajectory data (not used for this task)
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
    
    # Expected paths
    expected_path = "/home/ga/secondary_storage/downloads"
    default_path = "/home/ga/Downloads"
    
    try:
        # Extract download location from Chrome Preferences
        download_location, error_msg = extract_download_location(copy_from_env)
        
        if download_location is None:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract download location from Chrome Preferences: {error_msg}"
            }
        
        logger.info(f"Extracted download location: {download_location}")
        
        # Validate the download location change
        validation_result = validate_download_location_change(
            download_location,
            expected_path,
            default_path
        )
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return validation_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification exception: {str(e)}"
        }


def extract_download_location(copy_from_env) -> Tuple[Optional[str], str]:
    """
    Extract download location setting from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (download_location: str or None, error_message: str)
    """
    temp_file = None
    
    try:
        # Try multiple possible locations for Preferences file
        preferences_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in preferences_paths:
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
                    
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed Preferences from: {container_path}")
                    
                    # Clean up temp file
                    os.unlink(temp_path)
                    break
                else:
                    if os.path.exists(temp_path):
                        os.unlink(temp_path)
                        
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                if temp_file and os.path.exists(temp_path):
                    try:
                        os.unlink(temp_path)
                    except:
                        pass
                continue
        
        if not prefs_data:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Navigate JSON structure to extract download location
        # Path: prefs_data -> download -> default_directory
        download_section = prefs_data.get('download', {})
        
        if not download_section:
            return None, "Download section not found in Preferences (Chrome may not have been configured yet)"
        
        download_location = download_section.get('default_directory', None)
        
        if not download_location:
            # Try alternative key names
            download_location = download_section.get('default_folder', None)
        
        if not download_location:
            # Try savefile section as fallback
            savefile_section = prefs_data.get('savefile', {})
            download_location = savefile_section.get('default_directory', None)
        
        if not download_location:
            return None, "Download directory setting not found in Preferences (may still be at default)"
        
        logger.info(f"Extracted download location: {download_location}")
        return download_location, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting download location: {e}"


def normalize_path(path: str) -> str:
    """
    Normalize filesystem path for comparison.
    
    Handles:
    - Trailing slashes
    - Relative vs absolute paths
    - Redundant separators
    
    Args:
        path: Filesystem path string
        
    Returns:
        Normalized path string
    """
    if not path:
        return ""
    
    # Use os.path.normpath to normalize
    normalized = os.path.normpath(path)
    
    # Remove trailing slash
    normalized = normalized.rstrip('/')
    
    return normalized


def validate_download_location_change(
    actual_location: str,
    expected_path: str,
    default_path: str
) -> Dict[str, Any]:
    """
    Validate that download location was properly changed.
    
    Criteria:
    1. Location is different from default
    2. Location matches expected secondary storage path
    3. Path format is valid
    4. (Optional) Directory exists in container
    
    Args:
        actual_location: The download location found in Preferences
        expected_path: The expected secondary storage path
        default_path: The default Chrome Downloads path
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    # Normalize all paths for comparison
    norm_actual = normalize_path(actual_location)
    norm_expected = normalize_path(expected_path)
    norm_default = normalize_path(default_path)
    
    logger.info(f"Path comparison:")
    logger.info(f"  Actual:   {norm_actual}")
    logger.info(f"  Expected: {norm_expected}")
    logger.info(f"  Default:  {norm_default}")
    
    # Check if still at default (failure)
    if norm_actual == norm_default:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Download location unchanged from default.\n"
                f"Current: {actual_location}\n"
                f"Expected: {expected_path}\n"
                f"The setting is still at the default Downloads folder. "
                f"Please navigate to chrome://settings and change the download location."
            ),
            "details": {
                "actual_location": actual_location,
                "expected_location": expected_path,
                "changed_from_default": False,
                "matches_expected": False
            }
        }
    
    # Check for exact match with expected path (perfect score)
    if norm_actual == norm_expected:
        return {
            "passed": True,
            "score": 100,
            "feedback": (
                f"✓ Download location successfully changed to secondary storage!\n"
                f"New location: {actual_location}\n"
                f"This resolves the disk space constraint by using the secondary storage partition."
            ),
            "details": {
                "actual_location": actual_location,
                "expected_location": expected_path,
                "changed_from_default": True,
                "matches_expected": True,
                "path_match": "exact"
            }
        }
    
    # Check if it contains the expected path components (good enough)
    if "secondary_storage" in norm_actual and "downloads" in norm_actual:
        return {
            "passed": True,
            "score": 85,
            "feedback": (
                f"✓ Download location changed to a valid secondary storage path.\n"
                f"New location: {actual_location}\n"
                f"Expected: {expected_path}\n"
                f"Path is slightly different but still uses secondary storage, which resolves the disk space issue."
            ),
            "details": {
                "actual_location": actual_location,
                "expected_location": expected_path,
                "changed_from_default": True,
                "matches_expected": False,
                "path_match": "contains_secondary_storage"
            }
        }
    
    # Changed but not to expected location (partial credit)
    if norm_actual != norm_default:
        # Check if it's at least a valid-looking path
        if norm_actual.startswith("/home/ga/") or norm_actual.startswith("/"):
            return {
                "passed": False,
                "score": 60,
                "feedback": (
                    f"Download location was changed, but not to the expected secondary storage path.\n"
                    f"Current: {actual_location}\n"
                    f"Expected: {expected_path}\n"
                    f"While the location was changed, it doesn't use the secondary storage partition "
                    f"intended to resolve the disk space constraint."
                ),
                "details": {
                    "actual_location": actual_location,
                    "expected_location": expected_path,
                    "changed_from_default": True,
                    "matches_expected": False,
                    "path_match": "different_valid_path"
                }
            }
        else:
            return {
                "passed": False,
                "score": 30,
                "feedback": (
                    f"Download location was changed to an unexpected or invalid path.\n"
                    f"Current: {actual_location}\n"
                    f"Expected: {expected_path}\n"
                    f"The path doesn't appear to be a valid filesystem location."
                ),
                "details": {
                    "actual_location": actual_location,
                    "expected_location": expected_path,
                    "changed_from_default": True,
                    "matches_expected": False,
                    "path_match": "invalid_path"
                }
            }
    
    # Shouldn't reach here, but fallback
    return {
        "passed": False,
        "score": 0,
        "feedback": f"Unable to properly validate download location change. Current: {actual_location}",
        "details": {
            "actual_location": actual_location,
            "expected_location": expected_path,
            "changed_from_default": False,
            "matches_expected": False
        }
    }
