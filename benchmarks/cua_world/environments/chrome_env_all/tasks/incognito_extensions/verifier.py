#!/usr/bin/env python3
"""
Verifier for Chrome Incognito Extensions Management Task (incognito_extensions@1)
Task: Enable a Chrome extension for use in Incognito mode

Verification Strategy:
1. Copy Chrome Preferences file from container
2. Extract extension ID (from setup or auto-detect)
3. Parse Preferences JSON to find extensions.settings.<ext_id>.incognito
4. Verify incognito flag is set to true
5. Optionally verify incognito window was opened
6. Score based on multiple criteria

Scoring:
- Preferences file accessible: 20%
- Extension found in preferences: 20%
- Incognito permission enabled: 40%
- Incognito window opened (bonus): 20%

Pass threshold: 75% (3+ criteria with incognito=true)
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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for incognito_extensions@1 task.
    
    Verifies:
    1. Preferences file is accessible and valid JSON
    2. Extension exists in preferences
    3. Extension has incognito permission enabled
    4. Incognito window was opened (optional bonus)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
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

    try:
        # Get extension ID
        extension_id = get_extension_id(copy_from_env)
        logger.info(f"Target extension ID: {extension_id}")
        
        # Get Preferences file
        prefs_data, prefs_error = get_preferences_file(copy_from_env)
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {prefs_error}"
            }
        
        # Verify incognito permission
        verification_result = verify_incognito_permission(prefs_data, extension_id)
        
        # Check if incognito window was opened (bonus points)
        incognito_opened = check_incognito_window_opened(copy_from_env)
        
        # Calculate final score
        final_result = calculate_final_score(verification_result, incognito_opened)
        
        return final_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_verification_temp()


def get_extension_id(copy_from_env) -> str:
    """
    Get the extension ID from the setup script or auto-detect.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Extension ID string (or "unknown" if not found)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        # Try to copy extension ID file
        try:
            copy_from_env("/tmp/test_extension_id.txt", temp_file.name)
            with open(temp_file.name, 'r') as f:
                ext_id = f.read().strip()
            
            if ext_id and ext_id != "unknown" and len(ext_id) == 32:
                logger.info(f"Extension ID from setup: {ext_id}")
                return ext_id
        except Exception as e:
            logger.warning(f"Could not get extension ID from setup: {e}")
        
        return "unknown"
        
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def get_preferences_file(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Copy and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        # Try multiple possible locations
        locations = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for location in locations:
            try:
                logger.info(f"Trying to copy Preferences from: {location}")
                copy_from_env(location, temp_file.name)
                
                # Check if file was copied and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully loaded Preferences from: {location}")
                    return prefs_data, ""
                    
            except json.JSONDecodeError as e:
                logger.error(f"Preferences file is not valid JSON: {e}")
                return None, f"Preferences file corrupted (invalid JSON): {e}"
            except Exception as e:
                logger.debug(f"Failed to copy from {location}: {e}")
                continue
        
        return None, "Could not access Preferences file from any location"
        
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_incognito_permission(prefs_data: Dict, extension_id: str) -> Dict[str, Any]:
    """
    Verify that the extension has incognito permission enabled in Preferences.
    
    Args:
        prefs_data: Parsed Preferences JSON
        extension_id: Target extension ID
        
    Returns:
        Dict with verification results
    """
    result = {
        "prefs_valid": True,  # We already validated this
        "extension_found": False,
        "incognito_enabled": False,
        "extension_name": "",
        "actual_extension_id": extension_id
    }
    
    # Navigate to extensions settings
    extensions_settings = prefs_data.get('extensions', {}).get('settings', {})
    
    if not extensions_settings:
        logger.warning("No extensions settings found in Preferences")
        return result
    
    # If extension_id is unknown, try to find the test extension
    if extension_id == "unknown":
        logger.info("Extension ID unknown, attempting auto-detection...")
        for ext_id, ext_data in extensions_settings.items():
            ext_name = ext_data.get('manifest', {}).get('name', '')
            if 'incognito test' in ext_name.lower() or 'test extension' in ext_name.lower():
                extension_id = ext_id
                result['actual_extension_id'] = ext_id
                logger.info(f"Auto-detected extension ID: {ext_id}")
                break
    
    # Check if extension exists
    if extension_id not in extensions_settings:
        logger.error(f"Extension {extension_id} not found in settings")
        logger.info(f"Available extensions: {list(extensions_settings.keys())}")
        return result
    
    result['extension_found'] = True
    
    # Get extension data
    extension_data = extensions_settings[extension_id]
    result['extension_name'] = extension_data.get('manifest', {}).get('name', 'Unknown')
    
    # Check incognito permission
    incognito_allowed = extension_data.get('incognito', False)
    result['incognito_enabled'] = (incognito_allowed is True)
    
    logger.info(f"Extension '{result['extension_name']}' found")
    logger.info(f"Incognito permission: {incognito_allowed}")
    
    return result


def check_incognito_window_opened(copy_from_env) -> bool:
    """
    Check if an incognito window was opened during the task.
    
    Uses multiple detection methods:
    1. Check incognito_detected.txt flag file
    2. Check CDP tabs for multiple browser contexts
    3. Check window titles
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        True if incognito window was detected, False otherwise
    """
    # Method 1: Check flag file from export script
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/incognito_detected.txt", temp_file.name)
            with open(temp_file.name, 'r') as f:
                flag = f.read().strip().lower()
            
            if flag == "true":
                logger.info("✓ Incognito window detected (via wmctrl)")
                return True
        except:
            pass
        
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
    
    # Method 2: Check CDP tabs data
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/chrome_final_tabs.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                tabs_data = json.load(f)
            
            # Check if we have multiple page contexts (potential indicator of incognito)
            page_tabs = [t for t in tabs_data if t.get('type') == 'page']
            
            # Incognito mode creates separate contexts, often indicated by multiple tabs
            # or tabs with "incognito" in their metadata
            if len(page_tabs) >= 2:
                logger.info(f"✓ Multiple tabs detected ({len(page_tabs)}), possible incognito window")
                return True
                
        except:
            pass
        
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
    
    logger.info("⚠ Incognito window not definitively detected")
    return False


def calculate_final_score(verification_result: Dict[str, Any], incognito_opened: bool) -> Dict[str, Any]:
    """
    Calculate final score based on all verification criteria.
    
    Scoring breakdown:
    - Preferences valid: 20 points (base requirement)
    - Extension found: 20 points
    - Incognito enabled: 40 points (main objective)
    - Incognito window opened: 20 points (bonus)
    
    Pass threshold: 75 points (need incognito enabled + other criteria)
    
    Args:
        verification_result: Results from verify_incognito_permission
        incognito_opened: Whether incognito window was detected
        
    Returns:
        Final verification result dict
    """
    score = 0
    feedback_parts = []
    
    # Criterion 1: Preferences valid (20 points)
    if verification_result.get('prefs_valid', False):
        score += 20
        feedback_parts.append("✓ Preferences file valid and accessible")
    else:
        feedback_parts.append("✗ Preferences file corrupted or invalid")
    
    # Criterion 2: Extension found (20 points)
    if verification_result.get('extension_found', False):
        score += 20
        ext_name = verification_result.get('extension_name', 'Unknown')
        feedback_parts.append(f"✓ Extension found: '{ext_name}'")
    else:
        feedback_parts.append("✗ Extension not found in Preferences")
        feedback_parts.append(f"  Expected ID: {verification_result.get('actual_extension_id', 'unknown')}")
    
    # Criterion 3: Incognito enabled (40 points) - MAIN OBJECTIVE
    if verification_result.get('incognito_enabled', False):
        score += 40
        feedback_parts.append("✓ Incognito permission correctly enabled")
    else:
        if verification_result.get('extension_found', False):
            feedback_parts.append("✗ Incognito permission NOT enabled (this is the main task objective!)")
        else:
            feedback_parts.append("✗ Cannot verify incognito permission (extension not found)")
    
    # Criterion 4: Incognito window opened (20 points) - BONUS
    if incognito_opened:
        score += 20
        feedback_parts.append("✓ Incognito window successfully opened")
    else:
        feedback_parts.append("⚠ Incognito window not detected (optional, no penalty)")
    
    # Determine pass/fail
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nFinal score: {score}/100"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        if score < 40:
            feedback += "\n\nThe extension was not properly configured. Please ensure you:"
            feedback += "\n  1. Navigate to chrome://extensions"
            feedback += "\n  2. Find the 'Incognito Test Extension'"
            feedback += "\n  3. Click 'Details'"
            feedback += "\n  4. Enable the 'Allow in Incognito' toggle"
        elif score < 75:
            feedback += "\n\nYou're close! Make sure the 'Allow in Incognito' toggle is enabled."
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "prefs_valid": verification_result.get('prefs_valid', False),
            "extension_found": verification_result.get('extension_found', False),
            "incognito_enabled": verification_result.get('incognito_enabled', False),
            "incognito_window_opened": incognito_opened,
            "extension_id": verification_result.get('actual_extension_id', 'unknown'),
            "extension_name": verification_result.get('extension_name', 'Unknown')
        }
    }
