#!/usr/bin/env python3
"""
Verifier for Chrome Download Location Configuration Task (download_location_config@1)
Task: Configure Chrome to use a custom download directory

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract download.default_directory
- Validate that path differs from default /home/ga/Downloads
- Verify path is absolute, within user's home directory, and not a system directory
- Check that the specified directory would be accessible (simulated check)
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


def verify_task(traj, env_info, task_info):
    """
    Main verification function for download_location_config@1.
    
    Verifies that Chrome's download directory has been changed to a custom location.
    
    Criteria (4 total, need 3+ to pass):
    1. Download directory changed from default /home/ga/Downloads
    2. Path is valid (absolute, in home dir, not system dir)
    3. Directory exists (validated via path structure)
    4. Directory is accessible (validated via path permissions)
    
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

    username = 'ga'
    default_path = f'/home/{username}/Downloads'

    try:
        # Extract download directory from Chrome Preferences
        download_dir, error_msg = extract_download_directory(copy_from_env, username)
        
        if download_dir is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract download directory: {error_msg}"
            }
        
        logger.info(f"Extracted download directory: {download_dir}")
        
        # Perform multi-criteria verification
        criteria_results = []
        feedback_parts = []
        
        # Criterion 1: Changed from default
        changed_from_default = (download_dir != default_path)
        criteria_results.append(changed_from_default)
        
        if changed_from_default:
            feedback_parts.append(f"✓ Download directory changed to: {download_dir}")
        else:
            feedback_parts.append(f"✗ Download directory unchanged from default: {default_path}")
        
        # Criterion 2: Valid path format
        valid_path, path_issues = validate_path_format(download_dir, username)
        criteria_results.append(valid_path)
        
        if valid_path:
            feedback_parts.append("✓ Path format is valid and secure")
        else:
            feedback_parts.append(f"✗ Invalid path format: {', '.join(path_issues)}")
        
        # Criterion 3: Directory validation (structural check)
        # We validate based on path structure since we can't directly check filesystem in container
        dir_valid = validate_directory_structure(download_dir, username)
        criteria_results.append(dir_valid)
        
        if dir_valid:
            feedback_parts.append("✓ Directory structure appears valid")
        else:
            feedback_parts.append("✗ Directory structure validation failed")
        
        # Criterion 4: Accessibility check (simulated based on path characteristics)
        accessible = validate_accessibility(download_dir, username)
        criteria_results.append(accessible)
        
        if accessible:
            feedback_parts.append("✓ Directory appears accessible")
        else:
            feedback_parts.append("✗ Directory may not be accessible")
        
        # Calculate score
        criteria_met = sum(criteria_results)
        score = (criteria_met / 4.0) * 100
        passed = score >= 75  # Need at least 3/4 criteria
        
        # Build final feedback
        feedback = f"Download Location Configuration: {criteria_met}/4 criteria met\n"
        feedback += "\n".join(feedback_parts)
        
        if passed:
            feedback += f"\n\n✅ Task completed successfully!"
            feedback += f"\n   New location: {download_dir}"
            feedback += f"\n   Changed from: {default_path}"
        else:
            feedback += f"\n\n❌ Task incomplete or configuration invalid"
        
        # Clean up
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback,
            "details": {
                "download_directory": download_dir,
                "default_path": default_path,
                "changed": changed_from_default,
                "valid_format": valid_path,
                "criteria_met": criteria_met
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


def extract_download_directory(copy_from_env, username='ga'):
    """
    Extract download directory from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        username: Chrome user name
        
    Returns:
        Tuple of (download_dir: str or None, error_message: str)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            try:
                success, files, error = setup_chrome_verification(
                    copy_from_env,
                    ["Preferences"],
                    user=username,
                    profile="Default"
                )
                
                if success:
                    prefs_path = files["Preferences"]
                    prefs = parse_preferences(prefs_path)
                    download_settings = prefs.get('download', {})
                    download_dir = download_settings.get('default_directory', '')
                    
                    cleanup_verification_temp()
                    
                    if download_dir:
                        return download_dir, ""
                    else:
                        logger.warning("download.default_directory not found in Preferences")
            except Exception as e:
                logger.warning(f"Utility-based extraction failed: {e}, trying fallback")
        
        # Fallback: Manual extraction from multiple possible locations
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # List of possible container paths to try
        possible_paths = [
            "/tmp/chrome_preferences_download.json",
            f"/home/{username}/.config/google-chrome-cdp/Default/Preferences",
            f"/home/{username}/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            return None, "Could not access Preferences file from any known location"
        
        # Extract download directory from nested structure
        download_settings = prefs.get('download', {})
        download_dir = download_settings.get('default_directory', '')
        
        if not download_dir:
            return None, "download.default_directory field not found in Preferences"
        
        logger.info(f"Extracted download directory: {download_dir}")
        return download_dir, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting download directory: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def validate_path_format(path, username='ga'):
    """
    Validate that the download path has proper format.
    
    Args:
        path: Download directory path
        username: User name
        
    Returns:
        Tuple of (is_valid: bool, issues: list)
    """
    issues = []
    
    if not path:
        issues.append("path is empty")
        return False, issues
    
    # Check it's an absolute path
    if not os.path.isabs(path):
        issues.append("not an absolute path")
    
    # Check it's within user's home directory
    home_dir = f'/home/{username}'
    if not path.startswith(home_dir):
        issues.append("path outside user's home directory")
    
    # Check it's not a system directory
    system_dirs = ['/tmp', '/var', '/root', '/usr', '/bin', '/etc', '/sys', '/proc', '/dev']
    if any(path.startswith(d) for d in system_dirs):
        issues.append("path in system directory (not allowed)")
    
    # Check path doesn't contain suspicious patterns
    suspicious = ['..', '//', '~']
    if any(pattern in path for pattern in suspicious):
        issues.append("path contains suspicious patterns")
    
    # Check path length is reasonable
    if len(path) > 200:
        issues.append("path is excessively long")
    
    is_valid = len(issues) == 0
    return is_valid, issues


def validate_directory_structure(path, username='ga'):
    """
    Validate directory structure makes sense.
    
    Args:
        path: Download directory path
        username: User name
        
    Returns:
        bool: True if structure is valid
    """
    # Should be a subdirectory of home
    home_dir = f'/home/{username}'
    
    if not path.startswith(home_dir):
        return False
    
    # Path should be more than just home directory
    if path == home_dir:
        return False
    
    # Should have at least one directory component after home
    rel_path = path[len(home_dir):].strip('/')
    if not rel_path:
        return False
    
    # Directory name should be reasonable
    parts = rel_path.split('/')
    for part in parts:
        # Check for empty parts
        if not part:
            return False
        # Check for reasonable length
        if len(part) > 50:
            return False
        # Check it's not just dots
        if part.strip('.') == '':
            return False
    
    return True


def validate_accessibility(path, username='ga'):
    """
    Validate that directory should be accessible (heuristic check).
    
    Args:
        path: Download directory path
        username: User name
        
    Returns:
        bool: True if likely accessible
    """
    # Basic checks - if path format is valid, we assume accessibility
    # In production, this would execute: test -d {path} && test -w {path}
    
    # Path should be in user's home
    home_dir = f'/home/{username}'
    if not path.startswith(home_dir):
        return False
    
    # Should not be in hidden system directories
    hidden_system = ['.cache', '.local/lib', '.mozilla', '.config/google-chrome']
    rel_path = path[len(home_dir):].strip('/')
    
    for hidden in hidden_system:
        if rel_path.startswith(hidden):
            return False
    
    return True
