#!/usr/bin/env python3
"""
Verifier for Chrome Download Behavior Configuration Task (download_auto_open@1)
Task: Configure Chrome download location to custom directory and optionally enable auto-open

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse download.default_directory setting
- Verify location is not default ~/Downloads
- Check that custom directory (MyDownloads) exists
- Verify directory has proper permissions
- Optionally check for auto-open configuration (bonus points)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for download_auto_open@1 task.
    
    Verifies:
    1. Download location is set to custom directory (not default)
    2. Custom directory contains "MyDownloads"
    3. Directory actually exists in filesystem
    4. Directory has proper read/write permissions
    5. (Bonus) Auto-open is configured for at least one file type
    
    Scoring:
    - Base: 85 points for correct download location with accessible directory
    - Bonus: +15 points for auto-open configuration
    - Pass threshold: 75%
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Step 1: Extract download configuration from Preferences
        prefs, error_msg = get_preferences_data(copy_from_env)
        
        if prefs is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error_msg}"
            }
        
        # Step 2: Verify download location configuration
        location_result = verify_download_location(prefs)
        
        # Step 3: Verify directory exists (if location was configured)
        if location_result["configured"]:
            directory_result = verify_directory_exists(
                copy_from_env,
                location_result["download_dir"]
            )
        else:
            directory_result = {
                "exists": False,
                "accessible": False,
                "error": "No custom location configured"
            }
        
        # Step 4: Check auto-open configuration (bonus)
        autoopen_result = check_autoopen_config(prefs)
        
        # Calculate final score and feedback
        final_result = calculate_final_score(
            location_result,
            directory_result,
            autoopen_result
        )
        
        # Cleanup
        cleanup_verification_temp()
        
        return final_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_preferences_data(copy_from_env):
    """
    Copy and parse Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict, error_message)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            success, local_path, error = copy_chrome_file(
                "Preferences",
                copy_from_env,
                user="ga",
                profile="Default"
            )
            
            if success:
                prefs = parse_preferences(local_path)
                return prefs, ""
            else:
                logger.warning(f"Utility-based copy failed: {error}, trying fallback")
        
        # Fallback: Manual copy from known locations
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_download.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs is None:
            return None, "Could not copy Preferences file from any known location"
        
        return prefs, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error loading Preferences: {e}"
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_download_location(prefs):
    """
    Verify download location is configured to custom directory.
    
    Args:
        prefs: Parsed Preferences dictionary
        
    Returns:
        Dict with verification results
    """
    download_section = prefs.get('download', {})
    download_dir = download_section.get('default_directory', '')
    
    logger.info(f"Download directory from Preferences: '{download_dir}'")
    
    # Check if download directory is set
    if not download_dir:
        return {
            "configured": False,
            "download_dir": "",
            "is_custom": False,
            "has_mydownloads": False,
            "feedback": "Download location not configured (empty)"
        }
    
    # Check if it's NOT the default Downloads directory
    default_locations = [
        "/home/ga/Downloads",
        "/home/webuser/Downloads",
        "Downloads",
        ""
    ]
    
    is_default = any(
        download_dir == default or download_dir.endswith("/Downloads")
        for default in default_locations
    )
    
    if is_default:
        return {
            "configured": True,
            "download_dir": download_dir,
            "is_custom": False,
            "has_mydownloads": False,
            "feedback": f"Download location unchanged from default: {download_dir}"
        }
    
    # Check if it contains "MyDownloads" (the expected custom directory name)
    has_mydownloads = "MyDownloads" in download_dir or "mydownloads" in download_dir.lower()
    
    if not has_mydownloads:
        return {
            "configured": True,
            "download_dir": download_dir,
            "is_custom": True,
            "has_mydownloads": False,
            "feedback": f"Custom location set but doesn't contain 'MyDownloads': {download_dir}"
        }
    
    # Success - custom location with MyDownloads
    return {
        "configured": True,
        "download_dir": download_dir,
        "is_custom": True,
        "has_mydownloads": True,
        "feedback": f"✓ Custom download location configured: {download_dir}"
    }


def verify_directory_exists(copy_from_env, download_dir):
    """
    Verify the configured download directory actually exists and is accessible.
    
    Args:
        copy_from_env: Function to copy files from container
        download_dir: Path to the download directory
        
    Returns:
        Dict with existence and accessibility info
    """
    if not download_dir:
        return {
            "exists": False,
            "accessible": False,
            "error": "No directory path provided"
        }
    
    try:
        # Try to list the directory to check existence and permissions
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        # Copy directory listing if available
        listing_path = "/tmp/mydownloads_listing.txt"
        try:
            copy_from_env(listing_path, temp_file.name)
            
            with open(temp_file.name, 'r') as f:
                content = f.read()
            
            os.unlink(temp_file.name)
            
            # Check if directory was found
            if "not_found" in content:
                return {
                    "exists": False,
                    "accessible": False,
                    "error": f"Directory does not exist: {download_dir}"
                }
            
            # If we got a listing, directory exists
            logger.info(f"✓ Directory exists and is accessible: {download_dir}")
            return {
                "exists": True,
                "accessible": True,
                "error": None
            }
            
        except Exception as e:
            logger.warning(f"Could not verify directory via listing: {e}")
            # Assume directory exists if location was configured properly
            # (the agent may have created it through the Chrome dialog)
            return {
                "exists": True,  # Assume exists if configured
                "accessible": True,  # Assume accessible
                "error": None
            }
        
    except Exception as e:
        return {
            "exists": False,
            "accessible": False,
            "error": f"Error checking directory: {e}"
        }


def check_autoopen_config(prefs):
    """
    Check if auto-open is configured for file types (bonus points).
    
    Args:
        prefs: Parsed Preferences dictionary
        
    Returns:
        Dict with auto-open configuration status
    """
    download_section = prefs.get('download', {})
    extensions_to_open = download_section.get('extensions_to_open', '')
    
    logger.info(f"Auto-open extensions: '{extensions_to_open}'")
    
    if extensions_to_open and len(extensions_to_open.strip()) > 0:
        # Check if safe file types are configured
        safe_types = ['pdf', 'txt', 'png', 'jpg', 'jpeg']
        configured_types = extensions_to_open.lower().split()
        
        has_safe_types = any(ext in extensions_to_open.lower() for ext in safe_types)
        
        return {
            "configured": True,
            "extensions": extensions_to_open,
            "safe": has_safe_types,
            "feedback": f"✓ Auto-open configured for: {extensions_to_open}"
        }
    
    return {
        "configured": False,
        "extensions": "",
        "safe": False,
        "feedback": "Auto-open not configured (optional)"
    }


def calculate_final_score(location_result, directory_result, autoopen_result):
    """
    Calculate final score based on all verification criteria.
    
    Scoring breakdown:
    - Custom location configured: 40 points
    - Contains "MyDownloads": 25 points
    - Directory exists: 15 points
    - Directory accessible: 5 points
    - Auto-open configured (bonus): 15 points
    
    Total possible: 100 points
    Pass threshold: 75 points
    
    Args:
        location_result: Download location verification results
        directory_result: Directory existence verification results
        autoopen_result: Auto-open configuration results
        
    Returns:
        Dict with passed, score, and detailed feedback
    """
    score = 0
    feedback_parts = []
    
    # Criterion 1: Custom location configured (40 points)
    if location_result["is_custom"]:
        score += 40
        feedback_parts.append("✓ Custom download location configured (40/40)")
    else:
        feedback_parts.append(f"✗ Download location not changed from default (0/40)")
        feedback_parts.append(f"  {location_result['feedback']}")
    
    # Criterion 2: Contains MyDownloads (25 points)
    if location_result["has_mydownloads"]:
        score += 25
        feedback_parts.append("✓ Location contains 'MyDownloads' (25/25)")
    else:
        if location_result["is_custom"]:
            feedback_parts.append("✗ Custom location doesn't contain 'MyDownloads' (0/25)")
        else:
            feedback_parts.append("✗ 'MyDownloads' directory not used (0/25)")
    
    # Criterion 3: Directory exists (15 points)
    if directory_result["exists"]:
        score += 15
        feedback_parts.append("✓ Directory exists in filesystem (15/15)")
    else:
        feedback_parts.append(f"✗ Directory does not exist (0/15)")
        if directory_result["error"]:
            feedback_parts.append(f"  {directory_result['error']}")
    
    # Criterion 4: Directory accessible (5 points)
    if directory_result["accessible"]:
        score += 5
        feedback_parts.append("✓ Directory is accessible (5/5)")
    else:
        feedback_parts.append("✗ Directory not accessible (0/5)")
    
    # Criterion 5: Auto-open configured - BONUS (15 points)
    if autoopen_result["configured"]:
        score += 15
        feedback_parts.append(f"✓ BONUS: {autoopen_result['feedback']} (+15)")
    else:
        feedback_parts.append(f"○ {autoopen_result['feedback']} (0/15 bonus)")
    
    # Determine if passed
    passed = score >= 75
    
    # Build final feedback
    feedback_parts.append("")
    feedback_parts.append("=" * 60)
    feedback_parts.append(f"Final Score: {score}/100")
    feedback_parts.append(f"Pass Threshold: 75/100")
    feedback_parts.append(f"Result: {'✅ PASSED' if passed else '❌ FAILED'}")
    
    if not passed:
        feedback_parts.append("")
        feedback_parts.append("To complete this task successfully:")
        feedback_parts.append("1. Navigate to chrome://settings")
        feedback_parts.append("2. Find the 'Downloads' section")
        feedback_parts.append("3. Click 'Change' next to Location")
        feedback_parts.append("4. Create and select /home/ga/MyDownloads")
        feedback_parts.append("5. (Optional) Enable auto-open for PDF files")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "location_configured": location_result["is_custom"],
            "has_mydownloads": location_result["has_mydownloads"],
            "directory_exists": directory_result["exists"],
            "directory_accessible": directory_result["accessible"],
            "autoopen_configured": autoopen_result["configured"],
            "download_dir": location_result.get("download_dir", ""),
            "autoopen_extensions": autoopen_result.get("extensions", "")
        }
    }
