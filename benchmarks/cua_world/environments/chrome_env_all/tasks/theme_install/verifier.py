#!/usr/bin/env python3
"""
Verifier for Chrome Theme Installation Task (theme_install@1)
Task: Install a custom theme from Chrome Web Store to personalize browser appearance

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON to find theme extension configuration
- Verify theme extension ID exists in extensions.settings
- Verify theme has valid colors or images configuration
- Check that theme is enabled (state == 1)
- Optionally verify theme extension files exist
- Ensure theme is not the default Chrome appearance

Scoring:
- 100%: Theme fully installed, enabled, with valid configuration and files
- 85-95%: Theme installed and enabled but file verification limited
- 60-75%: Theme configured but may be disabled or incomplete
- 0-50%: No theme found or configuration invalid
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
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences,
        get_chrome_profile_path
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
    Main verification function for theme_install@1 task.
    
    Verifies that a custom Chrome theme has been successfully installed.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get Preferences file from container
        prefs_data, error_msg = get_preferences_file(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences: {error_msg}"
            }
        
        # Verify theme installation in Preferences
        verification_result = verify_theme_in_preferences(prefs_data)
        
        if not verification_result["theme_found"]:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": verification_result["feedback"]
            }
        
        # Try to verify extension files if theme was found
        theme_id = verification_result["theme_id"]
        files_verified = verify_theme_extension_files(copy_from_env, theme_id)
        
        # Calculate final score
        final_result = calculate_final_score(verification_result, files_verified)
        
        # Clean up temporary files
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


def get_preferences_file(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Retrieve and parse Chrome Preferences file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
    """
    temp_file = None
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_preferences_final.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    return prefs_data, ""
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        return None, "Could not access Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error reading Preferences: {e}"
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_theme_in_preferences(prefs_data: Dict) -> Dict[str, Any]:
    """
    Verify that a theme is configured in Chrome Preferences.
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON data
        
    Returns:
        Dict with verification results including:
        - theme_found: bool
        - theme_id: str or None
        - theme_name: str or None
        - has_colors: bool
        - has_images: bool
        - is_enabled: bool
        - feedback: str
    """
    result = {
        "theme_found": False,
        "theme_id": None,
        "theme_name": None,
        "has_colors": False,
        "has_images": False,
        "is_enabled": False,
        "feedback": ""
    }
    
    # Navigate to extensions settings
    extensions = prefs_data.get('extensions', {}).get('settings', {})
    
    if not extensions:
        result["feedback"] = "No extensions found in Preferences"
        return result
    
    # Look for theme extensions
    for ext_id, ext_data in extensions.items():
        manifest = ext_data.get('manifest', {})
        
        # Check if this extension has a 'theme' key (indicates it's a theme)
        if 'theme' in manifest:
            result["theme_found"] = True
            result["theme_id"] = ext_id
            result["theme_name"] = manifest.get('name', 'Unknown Theme')
            
            # Check theme configuration
            theme_config = manifest.get('theme', {})
            result["has_colors"] = bool(theme_config.get('colors'))
            result["has_images"] = bool(theme_config.get('images'))
            
            # Check if theme is enabled
            ext_state = ext_data.get('state', 0)
            result["is_enabled"] = (ext_state == 1)
            
            logger.info(f"Found theme: {result['theme_name']} (ID: {ext_id})")
            logger.info(f"  Has colors: {result['has_colors']}")
            logger.info(f"  Has images: {result['has_images']}")
            logger.info(f"  Is enabled: {result['is_enabled']}")
            
            # Found a theme, we can break
            break
    
    if not result["theme_found"]:
        result["feedback"] = "No custom theme found in Chrome extensions"
    elif not result["is_enabled"]:
        result["feedback"] = f"Theme '{result['theme_name']}' is installed but disabled"
    elif not (result["has_colors"] or result["has_images"]):
        result["feedback"] = f"Theme '{result['theme_name']}' has incomplete configuration"
    else:
        result["feedback"] = f"Theme '{result['theme_name']}' successfully installed and enabled"
    
    return result


def verify_theme_extension_files(copy_from_env, theme_id: str) -> Dict[str, Any]:
    """
    Verify that theme extension files exist in the Extensions directory.
    
    Args:
        copy_from_env: Function to copy files from container
        theme_id: Chrome extension ID for the theme
        
    Returns:
        Dict with file verification results
    """
    result = {
        "files_found": False,
        "manifest_valid": False,
        "manifest_name": None,
        "error": None
    }
    
    if not theme_id:
        result["error"] = "No theme ID provided"
        return result
    
    try:
        # Try to copy the theme extension manifest
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Possible manifest locations
        manifest_paths = [
            f"/tmp/theme_verification/extensions/{theme_id}/manifest.json"
        ]
        
        for container_path in manifest_paths:
            try:
                logger.info(f"Trying to copy theme manifest from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        manifest_data = json.load(f)
                    
                    result["files_found"] = True
                    
                    # Validate it's a theme manifest
                    if 'theme' in manifest_data:
                        result["manifest_valid"] = True
                        result["manifest_name"] = manifest_data.get('name', 'Unknown')
                        logger.info(f"✓ Theme manifest validated: {result['manifest_name']}")
                    else:
                        result["manifest_valid"] = False
                        logger.warning("Manifest found but doesn't contain theme configuration")
                    
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy manifest from {container_path}: {e}")
                continue
        
        if not result["files_found"]:
            logger.info("Could not verify theme extension files (not critical)")
            result["error"] = "Extension files not accessible for verification"
        
    except Exception as e:
        logger.warning(f"Error verifying theme files: {e}")
        result["error"] = str(e)
    finally:
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
    
    return result


def calculate_final_score(theme_result: Dict, files_result: Dict) -> Dict[str, Any]:
    """
    Calculate final score based on theme configuration and file verification.
    
    Args:
        theme_result: Results from verify_theme_in_preferences
        files_result: Results from verify_theme_extension_files
        
    Returns:
        Dict with passed, score, and feedback
    """
    criteria = []
    feedback_parts = []
    
    # Criterion 1: Theme found in Preferences (critical)
    if theme_result["theme_found"]:
        criteria.append(True)
        feedback_parts.append(f"✓ Theme installed: {theme_result['theme_name']}")
    else:
        criteria.append(False)
        feedback_parts.append("✗ No custom theme found")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts)
        }
    
    # Criterion 2: Theme is enabled
    if theme_result["is_enabled"]:
        criteria.append(True)
        feedback_parts.append("✓ Theme is enabled")
    else:
        criteria.append(False)
        feedback_parts.append("✗ Theme is disabled")
    
    # Criterion 3: Theme has colors or images configuration
    if theme_result["has_colors"] or theme_result["has_images"]:
        criteria.append(True)
        config_details = []
        if theme_result["has_colors"]:
            config_details.append("colors")
        if theme_result["has_images"]:
            config_details.append("images")
        feedback_parts.append(f"✓ Theme configuration valid ({', '.join(config_details)})")
    else:
        criteria.append(False)
        feedback_parts.append("✗ Theme configuration incomplete")
    
    # Criterion 4: Extension files verified (optional, for bonus points)
    if files_result["files_found"] and files_result["manifest_valid"]:
        criteria.append(True)
        feedback_parts.append(f"✓ Theme extension files verified")
    else:
        criteria.append(False)
        feedback_parts.append(f"⚠ Extension files not fully verified ({files_result.get('error', 'unknown')})")
    
    # Calculate score
    # First 3 criteria are critical, 4th is bonus
    critical_met = sum(criteria[:3])
    bonus_met = criteria[3] if len(criteria) > 3 else False
    
    if critical_met == 3:
        if bonus_met:
            score = 100
        else:
            score = 90
        passed = True
    elif critical_met == 2:
        score = 75
        passed = True
    elif critical_met == 1:
        score = 40
        passed = False
    else:
        score = 0
        passed = False
    
    # Add summary
    feedback_parts.append("")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Critical criteria met: {critical_met}/3")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if passed:
        feedback_parts.append("")
        feedback_parts.append(f"Theme ID: {theme_result['theme_id'][:16]}...")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": {
            "theme_id": theme_result["theme_id"],
            "theme_name": theme_result["theme_name"],
            "is_enabled": theme_result["is_enabled"],
            "has_colors": theme_result["has_colors"],
            "has_images": theme_result["has_images"],
            "files_verified": files_result["files_found"]
        }
    }
