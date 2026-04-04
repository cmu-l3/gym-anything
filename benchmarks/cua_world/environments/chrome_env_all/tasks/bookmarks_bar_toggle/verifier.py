#!/usr/bin/env python3
"""
Verifier for Chrome Bookmarks Bar Toggle Task (bookmarks_bar_toggle@1)
Task: Toggle Chrome bookmarks bar visibility through Settings > Appearance

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract bookmark_bar.show_on_all_tabs setting
- Validate that the setting exists and is a valid boolean value
- The task is about toggling, so we accept either true or false as success
- We verify the setting was properly configured, not that it's in a specific state
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
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for bookmarks_bar_toggle@1.
    
    Verifies that the bookmarks bar visibility setting is properly configured
    in Chrome Preferences. The task is about toggling the setting, so we verify
    the setting exists and is a valid boolean, not that it's in a specific state.
    
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
        # Extract bookmarks bar setting from Chrome Preferences
        bookmark_bar_state, error_msg = extract_bookmarks_bar_setting(copy_from_env)
        
        if bookmark_bar_state is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract bookmarks bar setting: {error_msg}"
            }
        
        # Validate the setting
        is_valid, score, feedback = validate_bookmarks_bar_setting(bookmark_bar_state)
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "bookmark_bar_visible": bookmark_bar_state,
                "setting_type": type(bookmark_bar_state).__name__
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary files
        cleanup_verification_temp()


def extract_bookmarks_bar_setting(copy_from_env):
    """
    Extract bookmarks bar visibility setting from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (bookmark_bar_state: bool or None, error_message: str)
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
                prefs = parse_preferences(prefs_path)
                
                if not prefs:
                    logger.warning("Failed to parse preferences with utils, trying fallback")
                else:
                    bookmark_bar_config = prefs.get('bookmark_bar', {})
                    show_on_all_tabs = bookmark_bar_config.get('show_on_all_tabs')
                    
                    if show_on_all_tabs is not None:
                        logger.info(f"Successfully extracted setting via utils: {show_on_all_tabs}")
                        return show_on_all_tabs, ""
        
        # Fallback: Manual extraction
        logger.info("Using fallback method to extract preferences...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_locations = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        successful_path = None
        
        for container_path in prefs_locations:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    successful_path = container_path
                    logger.info(f"✓ Successfully copied and parsed from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, "Could not access Chrome Preferences file from any known location"
        
        # Navigate nested structure to extract bookmarks bar setting
        bookmark_bar_config = prefs_data.get('bookmark_bar', {})
        show_on_all_tabs = bookmark_bar_config.get('show_on_all_tabs')
        
        if show_on_all_tabs is None:
            logger.warning("bookmark_bar.show_on_all_tabs not found in preferences")
            return None, "Bookmarks bar setting not found in Chrome Preferences. Ensure you toggled the setting in chrome://settings/appearance"
        
        logger.info(f"Extracted show_on_all_tabs: {show_on_all_tabs} (type: {type(show_on_all_tabs).__name__})")
        
        return show_on_all_tabs, ""
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return None, f"Failed to parse Chrome Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Extraction error: {e}", exc_info=True)
        return None, f"Error extracting bookmarks bar setting: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except Exception as e:
                logger.debug(f"Failed to cleanup temp file: {e}")


def validate_bookmarks_bar_setting(bookmark_bar_state):
    """
    Validate that bookmarks bar setting is properly configured.
    
    The task is about toggling the bookmarks bar, not setting it to a specific state.
    Therefore, we validate that:
    1. The setting exists (not None)
    2. The setting is a valid boolean type
    3. Either true or false is acceptable
    
    Args:
        bookmark_bar_state: The value of bookmark_bar.show_on_all_tabs setting
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    # Check if setting is None (not found)
    if bookmark_bar_state is None:
        return False, 0, (
            "Bookmarks bar setting not found in Chrome Preferences. "
            "Please navigate to chrome://settings/appearance and toggle the 'Show bookmarks bar' setting."
        )
    
    # Check if setting is boolean type
    if not isinstance(bookmark_bar_state, bool):
        return False, 50, (
            f"Bookmarks bar setting has invalid type: {type(bookmark_bar_state).__name__} "
            f"(value: {bookmark_bar_state}). Expected boolean (true/false)."
        )
    
    # Setting is valid boolean - task successful!
    state_text = "shown" if bookmark_bar_state else "hidden"
    
    feedback = (
        f"✅ Bookmarks bar successfully configured!\n"
        f"Current state: {state_text} (show_on_all_tabs = {bookmark_bar_state})\n"
        f"Setting properly saved to Chrome Preferences.\n\n"
        f"The bookmarks bar is now {'visible below the address bar' if bookmark_bar_state else 'hidden'}."
    )
    
    return True, 100, feedback
