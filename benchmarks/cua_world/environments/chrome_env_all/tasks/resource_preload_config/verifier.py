#!/usr/bin/env python3
"""
Verifier for Chrome Resource Preloading Configuration Task (resource_preload_config@1)
Task: Configure Chrome's Extended preloading mode for maximum page load performance

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract network prediction settings
- Check for both legacy and modern preference keys
- Validate that Extended/Aggressive preloading is enabled
- Ensure setting value indicates maximum preloading aggressiveness
"""

import logging
import sys
import os
import json
import tempfile
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
        """Fallback cleanup function"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for resource_preload_config@1.
    
    Verifies that Chrome's network prediction/preloading is set to Extended mode.
    
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
        # Extract preloading settings from Chrome Preferences
        setting_value, setting_name, error_msg = extract_preloading_setting(copy_from_env)
        
        if setting_value is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract preloading setting: {error_msg}"
            }
        
        # Validate that Extended preloading is enabled
        is_valid, score, feedback = validate_extended_preloading(setting_value, setting_name)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "setting_name": setting_name,
                "setting_value": setting_value,
                "extended_enabled": is_valid
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


def extract_preloading_setting(copy_from_env) -> Tuple[Optional[int], Optional[str], str]:
    """
    Extract network prediction/preloading setting from Chrome Preferences file.
    
    Chrome stores preloading settings under different keys depending on version:
    - Older: net.network_prediction_options (0=Always, 1=WiFi only, 2=Never, 3=Default)
    - Newer: net.preload_pages (0=No preloading, 1=Standard, 2=Extended)
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (setting_value: int or None, setting_name: str or None, error_message: str)
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
                prefs = parse_preferences(prefs_path)
                
                if prefs:
                    # Try to extract preloading settings
                    net_settings = prefs.get('net', {})
                    
                    # Try modern key first
                    if 'preload_pages' in net_settings:
                        value = net_settings['preload_pages']
                        cleanup_verification_temp()
                        return value, 'preload_pages', ""
                    
                    # Try legacy key
                    if 'network_prediction_options' in net_settings:
                        value = net_settings['network_prediction_options']
                        cleanup_verification_temp()
                        return value, 'network_prediction_options', ""
                    
                    cleanup_verification_temp()
                    return None, None, "Network prediction settings not found in Preferences"
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations for Preferences file
        preferences_locations = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_location = None
        
        for location in preferences_locations:
            try:
                logger.info(f"Trying to copy Preferences from: {location}")
                copy_from_env(location, temp_file.name)
                
                # Verify file was copied and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_location = location
                    logger.info(f"✓ Successfully copied and parsed Preferences from: {location}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {location}: {e}")
                continue
        
        if prefs is None:
            return None, None, "Could not copy Preferences file from any known location"
        
        # Navigate nested structure to extract preloading settings
        net_settings = prefs.get('net', {})
        
        if not net_settings:
            return None, None, "No 'net' section found in Preferences (settings may not have been configured)"
        
        # Try modern key first (preload_pages)
        if 'preload_pages' in net_settings:
            value = net_settings['preload_pages']
            logger.info(f"Found preload_pages setting: {value}")
            return value, 'preload_pages', ""
        
        # Try legacy key (network_prediction_options)
        if 'network_prediction_options' in net_settings:
            value = net_settings['network_prediction_options']
            logger.info(f"Found network_prediction_options setting: {value}")
            return value, 'network_prediction_options', ""
        
        # Neither key found
        logger.warning("Network prediction/preload settings not found in preferences")
        return None, None, "Network prediction/preload settings not found in Preferences. The setting may not have been changed."
        
    except json.JSONDecodeError as e:
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Error extracting preloading setting: {e}", exc_info=True)
        return None, None, f"Error extracting preloading setting: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def validate_extended_preloading(setting_value: int, setting_name: str) -> Tuple[bool, int, str]:
    """
    Validate that Extended/Aggressive preloading is enabled.
    
    Chrome's preloading settings vary by version:
    
    Newer Chrome (preload_pages):
      0 = No preloading
      1 = Standard preloading  
      2 = Extended preloading (DESIRED)
    
    Older Chrome (network_prediction_options):
      0 = Always predict (Extended - DESIRED)
      1 = Predict on WiFi only (Standard)
      2 = Never predict (Disabled)
      3 = Default/unset
    
    Args:
        setting_value: Integer value from Preferences
        setting_name: Name of the setting key
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    logger.info(f"Validating {setting_name} = {setting_value}")
    
    if setting_name == 'preload_pages':
        # Modern Chrome: 2 = Extended preloading
        if setting_value == 2:
            return True, 100, f"✓ Extended preloading correctly enabled ({setting_name}={setting_value}). Maximum performance mode active!"
        elif setting_value == 1:
            return False, 50, f"✗ Preloading set to Standard mode ({setting_name}={setting_value}). Expected Extended preloading (value 2)."
        elif setting_value == 0:
            return False, 0, f"✗ Preloading is disabled ({setting_name}={setting_value}). Expected Extended preloading (value 2)."
        else:
            return False, 0, f"✗ Unexpected preload_pages value: {setting_value}. Expected 2 for Extended preloading."
    
    elif setting_name == 'network_prediction_options':
        # Older Chrome: 0 = Always predict (Extended)
        if setting_value == 0:
            return True, 100, f"✓ Extended preloading correctly enabled ({setting_name}={setting_value}). Maximum performance mode active!"
        elif setting_value == 1:
            return False, 50, f"✗ Network prediction set to WiFi only ({setting_name}={setting_value}). Expected Always predict (value 0)."
        elif setting_value == 2:
            return False, 0, f"✗ Network prediction is disabled ({setting_name}={setting_value}). Expected Always predict (value 0)."
        elif setting_value == 3:
            return False, 25, f"✗ Network prediction is at default/unset ({setting_name}={setting_value}). Expected Always predict (value 0)."
        else:
            return False, 0, f"✗ Unexpected network_prediction_options value: {setting_value}. Expected 0 for Extended preloading."
    
    else:
        return False, 0, f"✗ Unknown setting name: {setting_name}"
