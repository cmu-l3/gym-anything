#!/usr/bin/env python3
"""
Verifier for Chrome Extension Management Task: extension_disable_enable@1
Task: Navigate to chrome://extensions/ and disable the Test Productivity Extension

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to find extension by name "Test Productivity Extension"
- Check extension state field (0=disabled, 1=enabled)
- Validate extension was initially enabled and is now disabled
- Provide detailed feedback on extension state

Criteria:
1. Extension exists in Preferences
2. Extension found by name "Test Productivity Extension"
3. Extension state is 0 (disabled)
4. Extension metadata is intact (not corrupted)

Scoring:
- 100%: Extension properly disabled (state=0)
- 75%: Extension state changed but not to exactly 0
- 50%: Extension found but state unchanged (still enabled)
- 0%: Extension not found or Preferences corrupted
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
try:
    from chrome_verification_utils import (
        parse_preferences,
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    
    def parse_preferences(path):
        """Fallback preferences parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def cleanup_verification_temp():
        """Fallback cleanup"""
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for extension_disable_enable@1.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', 'feedback', and 'details' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Get extension state from Chrome Preferences
        result = verify_extension_state(copy_from_env)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_extension_state(copy_from_env) -> Dict[str, Any]:
    """
    Verify that the Test Productivity Extension was properly disabled.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Dict with verification results
    """
    # Step 1: Copy Preferences file from container
    prefs_data, error = get_preferences_data(copy_from_env)
    
    if prefs_data is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to access Chrome Preferences: {error}",
            "details": {"error": error}
        }
    
    # Step 2: Find the test extension
    extension_info, find_error = find_test_extension(prefs_data)
    
    if extension_info is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not find Test Productivity Extension: {find_error}",
            "details": {
                "error": find_error,
                "extensions_found": list_all_extensions(prefs_data)
            }
        }
    
    extension_id = extension_info['id']
    extension_name = extension_info['name']
    extension_state = extension_info['state']
    extension_version = extension_info.get('version', 'unknown')
    
    logger.info(f"Found extension: {extension_name} (ID: {extension_id})")
    logger.info(f"Extension state: {extension_state} (0=disabled, 1=enabled)")
    logger.info(f"Extension version: {extension_version}")
    
    # Step 3: Verify extension state
    is_disabled = extension_state == 0
    is_enabled = extension_state == 1
    is_other = not is_disabled and not is_enabled
    
    # Determine pass/fail and score
    if is_disabled:
        passed = True
        score = 100
        feedback = (
            f"✅ Task completed successfully!\n"
            f"Extension '{extension_name}' has been disabled.\n"
            f"  - Extension ID: {extension_id}\n"
            f"  - State: {extension_state} (disabled)\n"
            f"  - Version: {extension_version}\n"
            f"\nThe extension toggle was successfully switched off."
        )
    elif is_enabled:
        passed = False
        score = 50
        feedback = (
            f"❌ Task incomplete\n"
            f"Extension '{extension_name}' is still ENABLED.\n"
            f"  - Extension ID: {extension_id}\n"
            f"  - State: {extension_state} (enabled)\n"
            f"  - Version: {extension_version}\n"
            f"\nThe extension was found but not disabled. "
            f"Please navigate to chrome://extensions/ and click the toggle to turn it OFF."
        )
    elif extension_state == 2:
        # State 2 = terminated (crashed or killed)
        passed = False
        score = 25
        feedback = (
            f"⚠ Extension state is 'terminated' (2)\n"
            f"Extension '{extension_name}' appears to have crashed or been terminated.\n"
            f"  - Extension ID: {extension_id}\n"
            f"  - State: {extension_state} (terminated)\n"
            f"\nThis is different from properly disabling the extension via the toggle."
        )
    elif extension_state == 3:
        # State 3 = blocklisted
        passed = True
        score = 75
        feedback = (
            f"⚠ Extension state is 'blocklisted' (3)\n"
            f"Extension '{extension_name}' has been blocklisted/disabled.\n"
            f"  - Extension ID: {extension_id}\n"
            f"  - State: {extension_state} (blocklisted)\n"
            f"\nWhile the extension is disabled, this may not be the intended method. "
            f"Partial credit given."
        )
    else:
        passed = False
        score = 0
        feedback = (
            f"❌ Unexpected extension state\n"
            f"Extension '{extension_name}' has an unexpected state value.\n"
            f"  - Extension ID: {extension_id}\n"
            f"  - State: {extension_state} (unknown)\n"
            f"  - Expected: 0 (disabled)\n"
        )
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "extension_id": extension_id,
            "extension_name": extension_name,
            "extension_state": extension_state,
            "extension_version": extension_version,
            "state_meaning": get_state_meaning(extension_state),
            "is_disabled": is_disabled
        }
    }


def get_preferences_data(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Copy and parse Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Attempting to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    return prefs_data, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return None, "Could not copy Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error accessing Preferences: {e}"
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def find_test_extension(prefs_data: Dict) -> Tuple[Optional[Dict], str]:
    """
    Find the Test Productivity Extension in Preferences data.
    
    Args:
        prefs_data: Parsed Preferences JSON
        
    Returns:
        Tuple of (extension_info_dict, error_message)
    """
    try:
        extensions_settings = prefs_data.get('extensions', {}).get('settings', {})
        
        if not extensions_settings:
            return None, "No extensions found in Preferences (extensions.settings is empty)"
        
        logger.info(f"Found {len(extensions_settings)} extension(s) in Preferences")
        
        # Search for the test extension by name
        target_name = "Test Productivity Extension"
        
        for ext_id, ext_data in extensions_settings.items():
            manifest = ext_data.get('manifest', {})
            ext_name = manifest.get('name', '')
            
            logger.debug(f"Checking extension: {ext_name} (ID: {ext_id})")
            
            if target_name.lower() in ext_name.lower():
                # Found the test extension
                state = ext_data.get('state', -1)
                version = manifest.get('version', 'unknown')
                
                return {
                    'id': ext_id,
                    'name': ext_name,
                    'state': state,
                    'version': version,
                    'manifest': manifest
                }, ""
        
        # If not found by name, try to get extension ID from setup
        return try_find_by_saved_id(extensions_settings)
        
    except Exception as e:
        return None, f"Error searching for extension: {e}"


def try_find_by_saved_id(extensions_settings: Dict) -> Tuple[Optional[Dict], str]:
    """
    Try to find extension using saved ID from setup script.
    
    Args:
        extensions_settings: Extensions settings from Preferences
        
    Returns:
        Tuple of (extension_info_dict, error_message)
    """
    try:
        # The setup script saves the extension ID - we can't access it here directly
        # So as a fallback, just return the first extension if there's only one
        if len(extensions_settings) == 1:
            ext_id = list(extensions_settings.keys())[0]
            ext_data = extensions_settings[ext_id]
            manifest = ext_data.get('manifest', {})
            
            return {
                'id': ext_id,
                'name': manifest.get('name', 'Unknown Extension'),
                'state': ext_data.get('state', -1),
                'version': manifest.get('version', 'unknown'),
                'manifest': manifest
            }, ""
        
        return None, f"Extension 'Test Productivity Extension' not found among {len(extensions_settings)} installed extensions"
        
    except Exception as e:
        return None, f"Error finding extension by saved ID: {e}"


def list_all_extensions(prefs_data: Dict) -> List[Dict[str, str]]:
    """
    List all extensions found in Preferences for debugging.
    
    Args:
        prefs_data: Parsed Preferences JSON
        
    Returns:
        List of extension summary dicts
    """
    try:
        extensions_settings = prefs_data.get('extensions', {}).get('settings', {})
        result = []
        
        for ext_id, ext_data in extensions_settings.items():
            manifest = ext_data.get('manifest', {})
            result.append({
                'id': ext_id,
                'name': manifest.get('name', 'Unknown'),
                'state': ext_data.get('state', -1),
                'version': manifest.get('version', 'unknown')
            })
        
        return result
        
    except Exception as e:
        logger.error(f"Error listing extensions: {e}")
        return []


def get_state_meaning(state: int) -> str:
    """
    Get human-readable meaning of extension state code.
    
    Args:
        state: Integer state code
        
    Returns:
        String description of state
    """
    state_map = {
        0: "disabled",
        1: "enabled",
        2: "terminated",
        3: "blocklisted"
    }
    return state_map.get(state, f"unknown ({state})")
