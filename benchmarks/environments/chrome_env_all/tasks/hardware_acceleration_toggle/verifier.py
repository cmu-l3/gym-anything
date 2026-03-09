#!/usr/bin/env python3
"""
Verifier for Chrome Hardware Acceleration Configuration Task
Task: Disable hardware acceleration in Chrome Settings > System

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract hardware_acceleration_mode
- Validate that hardware acceleration is explicitly disabled
- Check both modern and legacy preference paths
- Ensure setting is explicitly set, not just default
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Tuple, Optional, Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
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
    Main verification function for hardware_acceleration_toggle@1.
    
    Verifies that Chrome's hardware acceleration has been explicitly disabled.
    
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
            "feedback": "❌ Copy function not available in environment"
        }

    try:
        # Extract hardware acceleration state from Preferences
        state = extract_hardware_acceleration_state(copy_from_env)
        
        if state is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Failed to access Chrome Preferences file. "
                           "Ensure Chrome was running and settings were accessible."
            }
        
        # Validate the state
        result = validate_hardware_acceleration_state(state)
        
        # Clean up any temporary files
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def extract_hardware_acceleration_state(copy_from_env) -> Optional[Dict[str, Any]]:
    """
    Extract hardware acceleration state from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict with state information or None if extraction failed
        {
            'found': bool,          # Whether setting was found
            'enabled': bool,        # Current state (if found)
            'explicit': bool,       # Whether explicitly set or default
            'location': str         # JSON path where found
        }
    """
    temp_file = None
    
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            try:
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
                        state = parse_hardware_acceleration_from_prefs(prefs)
                        return state
                    else:
                        logger.warning("Utility-based extraction got empty preferences")
            except Exception as e:
                logger.warning(f"Utility-based extraction failed: {e}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
            "/home/ga/.config/chromium/Default/Preferences"
        ]
        
        prefs = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            logger.error("Could not load Preferences from any known location")
            return None
        
        # Parse hardware acceleration state
        state = parse_hardware_acceleration_from_prefs(prefs)
        state['source'] = source_path
        
        return state
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse Preferences JSON: {e}")
        return None
    except Exception as e:
        logger.error(f"Error extracting hardware acceleration state: {e}")
        return None
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def parse_hardware_acceleration_from_prefs(prefs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse hardware acceleration state from preferences dictionary.
    
    Checks multiple possible locations:
    1. hardware_acceleration_mode.enabled (modern Chrome)
    2. hardware.acceleration_enabled (legacy Chrome)
    
    Args:
        prefs: Parsed preferences dictionary
        
    Returns:
        Dict with state information
    """
    # Check primary location: hardware_acceleration_mode
    hw_mode = prefs.get('hardware_acceleration_mode', {})
    
    if isinstance(hw_mode, dict) and 'enabled' in hw_mode:
        enabled = hw_mode['enabled']
        logger.info(f"Found hardware_acceleration_mode.enabled = {enabled}")
        return {
            'found': True,
            'enabled': bool(enabled),
            'explicit': True,
            'location': 'hardware_acceleration_mode.enabled'
        }
    
    # Check if hardware_acceleration_mode exists but is just a boolean (some Chrome versions)
    if isinstance(hw_mode, bool):
        logger.info(f"Found hardware_acceleration_mode = {hw_mode} (boolean)")
        return {
            'found': True,
            'enabled': hw_mode,
            'explicit': True,
            'location': 'hardware_acceleration_mode'
        }
    
    # Check legacy location: hardware.acceleration_enabled
    hw_legacy = prefs.get('hardware', {})
    if isinstance(hw_legacy, dict) and 'acceleration_enabled' in hw_legacy:
        enabled = hw_legacy['acceleration_enabled']
        logger.info(f"Found hardware.acceleration_enabled = {enabled} (legacy)")
        return {
            'found': True,
            'enabled': bool(enabled),
            'explicit': True,
            'location': 'hardware.acceleration_enabled'
        }
    
    # Setting not found - using Chrome default (enabled)
    logger.warning("Hardware acceleration setting not found in Preferences (using default)")
    return {
        'found': False,
        'enabled': True,  # Chrome default
        'explicit': False,
        'location': None
    }


def validate_hardware_acceleration_state(state: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate that hardware acceleration has been properly disabled.
    
    Args:
        state: Hardware acceleration state dictionary
        
    Returns:
        Verification result with passed, score, and feedback
    """
    # Criterion 1: Setting must be found (explicitly set)
    if not state['found']:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Hardware acceleration setting not found in Preferences.\n"
                       "The toggle was not changed, or Chrome did not save the setting.\n"
                       "Please navigate to Settings → System and toggle 'Use hardware acceleration when available'.",
            "details": state
        }
    
    # Criterion 2: Setting must be explicitly set (not default)
    if not state['explicit']:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Hardware acceleration setting appears to be in default state.\n"
                       "The toggle was not explicitly changed.\n"
                       "Please navigate to Settings → System and toggle the setting.",
            "details": state
        }
    
    # Criterion 3: Setting must be disabled
    if state['enabled']:
        return {
            "passed": False,
            "score": 50,
            "feedback": f"⚠️ Hardware acceleration is currently ENABLED.\n"
                       f"Task requires DISABLING it.\n"
                       f"Setting found at: {state['location']}\n"
                       f"Please toggle it OFF in Settings → System.",
            "details": state
        }
    
    # Success - hardware acceleration is disabled!
    return {
        "passed": True,
        "score": 100,
        "feedback": f"✅ Hardware acceleration successfully disabled!\n"
                   f"Setting verified at: {state['location']}\n"
                   f"Status: Explicitly set to DISABLED\n"
                   f"\n"
                   f"Note: This change will take effect after Chrome restart.\n"
                   f"Hardware acceleration is now disabled, which may help with:\n"
                   f"  - Graphics driver compatibility issues\n"
                   f"  - Screen flickering or visual artifacts\n"
                   f"  - Testing software rendering performance\n"
                   f"  - Remote desktop session optimization",
        "details": state
    }
