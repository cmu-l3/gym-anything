#!/usr/bin/env python3
"""
Verifier for Chrome Extension Load Unpacked Task (extension_load_unpacked@1)
Task: Load unpacked Chrome extension in developer mode

Verification Strategy:
- Copy Chrome Preferences file to check extension registration
- Copy Extensions directory to find installed extension
- Parse manifest.json to verify extension name
- Check extension enabled state in Preferences
- Validate extension installation method (unpacked/load)
"""

import logging
import sys
import os
import json
import tempfile
import shutil
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        get_chrome_profile_path,
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
        temp_dir = os.path.join(os.getcwd(), "temp_chrome_verification")
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)


def find_extension_by_name(extensions_dir: str, target_name: str = "Test Extension") -> Tuple[bool, Optional[str], Optional[str]]:
    """
    Scan Chrome Extensions directory for extension with matching name.
    
    Args:
        extensions_dir: Path to Chrome Extensions directory
        target_name: Expected extension name
        
    Returns:
        Tuple of (found, extension_id, manifest_path)
    """
    if not os.path.exists(extensions_dir):
        logger.warning(f"Extensions directory does not exist: {extensions_dir}")
        return False, None, None
    
    try:
        # List all extension IDs (top-level directories)
        extension_ids = [d for d in os.listdir(extensions_dir) 
                        if os.path.isdir(os.path.join(extensions_dir, d))]
        
        logger.info(f"Found {len(extension_ids)} extension ID(s) in Extensions directory")
        
        for ext_id in extension_ids:
            ext_path = os.path.join(extensions_dir, ext_id)
            
            # Extensions have version subdirectories (e.g., "1.0.0_0")
            try:
                versions = [v for v in os.listdir(ext_path) 
                           if os.path.isdir(os.path.join(ext_path, v))]
                
                for version in versions:
                    manifest_path = os.path.join(ext_path, version, "manifest.json")
                    
                    if os.path.exists(manifest_path):
                        try:
                            with open(manifest_path, 'r', encoding='utf-8') as f:
                                manifest = json.load(f)
                            
                            ext_name = manifest.get('name', '')
                            logger.info(f"  Extension {ext_id}/{version}: {ext_name}")
                            
                            if ext_name == target_name:
                                logger.info(f"✓ Found matching extension: {ext_id}")
                                return True, ext_id, manifest_path
                                
                        except json.JSONDecodeError as e:
                            logger.warning(f"Invalid manifest at {manifest_path}: {e}")
                        except Exception as e:
                            logger.warning(f"Error reading manifest at {manifest_path}: {e}")
            except Exception as e:
                logger.warning(f"Error scanning extension {ext_id}: {e}")
        
        logger.info(f"Extension with name '{target_name}' not found")
        return False, None, None
        
    except Exception as e:
        logger.error(f"Error scanning Extensions directory: {e}")
        return False, None, None


def validate_manifest(manifest_path: str) -> Tuple[bool, Optional[str], Optional[str], Optional[str]]:
    """
    Parse and validate extension manifest.json.
    
    Args:
        manifest_path: Path to manifest.json file
        
    Returns:
        Tuple of (valid, name, version, error_message)
    """
    try:
        with open(manifest_path, 'r', encoding='utf-8') as f:
            manifest = json.load(f)
        
        # Check required fields for Manifest V3
        required_fields = ['name', 'version', 'manifest_version']
        missing = [f for f in required_fields if f not in manifest]
        
        if missing:
            return False, None, None, f"Missing required fields: {', '.join(missing)}"
        
        name = manifest.get('name')
        version = manifest.get('version')
        manifest_version = manifest.get('manifest_version')
        
        # Validate manifest version (should be 2 or 3)
        if manifest_version not in [2, 3]:
            return False, name, version, f"Invalid manifest_version: {manifest_version} (expected 2 or 3)"
        
        logger.info(f"Manifest validation: name={name}, version={version}, manifest_version={manifest_version}")
        return True, name, version, None
        
    except json.JSONDecodeError as e:
        return False, None, None, f"Invalid JSON: {e}"
    except Exception as e:
        return False, None, None, f"Error reading manifest: {e}"


def check_extension_in_preferences(prefs_path: str, extension_id: str) -> Tuple[bool, bool, Dict]:
    """
    Verify extension is registered and enabled in Chrome Preferences.
    
    Args:
        prefs_path: Path to Chrome Preferences file
        extension_id: Extension ID to check
        
    Returns:
        Tuple of (registered, enabled, metadata)
    """
    try:
        prefs = parse_preferences(prefs_path)
        
        # Navigate to extensions settings
        extensions = prefs.get('extensions', {}).get('settings', {})
        
        if extension_id not in extensions:
            logger.info(f"Extension {extension_id} not found in Preferences")
            return False, False, {}
        
        ext_data = extensions[extension_id]
        
        # Check state (1 = enabled, 0 = disabled)
        state = ext_data.get('state', 0)
        enabled = (state == 1)
        
        # Check location (5 = unpacked/load, 1 = internal, 4 = external/install)
        location = ext_data.get('location', 0)
        is_unpacked = (location == 5)
        
        # Extract other metadata
        path = ext_data.get('path', '')
        from_webstore = ext_data.get('from_webstore', False)
        
        metadata = {
            'state': state,
            'enabled': enabled,
            'location': location,
            'is_unpacked': is_unpacked,
            'path': path,
            'from_webstore': from_webstore
        }
        
        logger.info(f"Extension in Preferences: state={state}, location={location}, enabled={enabled}, unpacked={is_unpacked}")
        
        # For this task, we want enabled AND loaded as unpacked
        return True, (enabled and is_unpacked), metadata
        
    except Exception as e:
        logger.error(f"Error checking Preferences: {e}")
        return False, False, {}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for extension_load_unpacked@1 task.
    
    Verification Criteria (5 total, need 4+ to pass):
    1. Extension directory exists in Chrome profile
    2. Manifest is valid and accessible
    3. Extension is registered in Preferences
    4. Extension is enabled
    5. Extension name matches "Test Extension"
    
    Args:
        traj: Trajectory data (not used)
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

    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    try:
        # Create temporary directory for verification
        temp_dir = tempfile.mkdtemp(prefix="ext_verify_")
        logger.info(f"Created temporary directory: {temp_dir}")
        
        # Step 1: Copy Preferences file
        prefs_path = os.path.join(temp_dir, "Preferences")
        try:
            copy_from_env("/tmp/chrome_preferences.json", prefs_path)
            logger.info("✓ Preferences file copied")
        except Exception as e:
            logger.error(f"Failed to copy Preferences: {e}")
            feedback_parts.append("✗ Could not access Chrome Preferences file")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts) + f"\nError: {str(e)}",
                "criteria_met": 0,
                "total_criteria": total_criteria
            }
        
        # Step 2: Determine Chrome profile location
        profile_location = None
        try:
            profile_loc_file = os.path.join(temp_dir, "profile_location.txt")
            copy_from_env("/tmp/chrome_profile_location.txt", profile_loc_file)
            with open(profile_loc_file, 'r') as f:
                profile_location = f.read().strip()
            logger.info(f"Chrome profile location: {profile_location}")
        except Exception as e:
            logger.warning(f"Could not determine profile location: {e}")
            # Try default locations
            profile_location = "/home/ga/.config/google-chrome-cdp/Default"
        
        # Step 3: Copy Extensions directory
        extensions_dir = os.path.join(temp_dir, "Extensions")
        container_ext_path = f"{profile_location}/Extensions"
        
        try:
            copy_from_env(container_ext_path, extensions_dir)
            logger.info(f"✓ Extensions directory copied from {container_ext_path}")
        except Exception as e:
            logger.error(f"Failed to copy Extensions directory: {e}")
            # Try alternative location
            try:
                alt_path = "/home/ga/.config/google-chrome/Default/Extensions"
                copy_from_env(alt_path, extensions_dir)
                logger.info(f"✓ Extensions directory copied from alternative location")
            except Exception as e2:
                feedback_parts.append("✗ Could not access Chrome Extensions directory")
                return {
                    "passed": False,
                    "score": int((criteria_met / total_criteria) * 100),
                    "feedback": "\n".join(feedback_parts) + f"\nError: {str(e2)}",
                    "criteria_met": criteria_met,
                    "total_criteria": total_criteria
                }
        
        # Criterion 1: Extension directory exists
        found_ext, ext_id, manifest_path = find_extension_by_name(extensions_dir, "Test Extension")
        
        if found_ext and ext_id:
            criteria_met += 1
            feedback_parts.append(f"✓ Extension directory found (ID: {ext_id})")
        else:
            feedback_parts.append("✗ Extension directory not found in Chrome profile")
            # Cannot proceed with further checks
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": "\n".join(feedback_parts) + "\n\nThe extension was not loaded. Please ensure you:\n1. Navigated to chrome://extensions\n2. Enabled Developer mode\n3. Clicked 'Load unpacked'\n4. Selected /home/ga/test_extension/",
                "criteria_met": criteria_met,
                "total_criteria": total_criteria
            }
        
        # Criterion 2: Manifest is valid
        valid_manifest, name, version, error = validate_manifest(manifest_path)
        if valid_manifest:
            criteria_met += 1
            feedback_parts.append(f"✓ Manifest valid (name: '{name}', version: {version})")
        else:
            feedback_parts.append(f"✗ Manifest invalid or unreadable: {error}")
        
        # Criterion 3 & 4: Check extension in Preferences
        registered, enabled, metadata = check_extension_in_preferences(prefs_path, ext_id)
        
        if registered:
            criteria_met += 1
            feedback_parts.append("✓ Extension registered in Chrome Preferences")
        else:
            feedback_parts.append("✗ Extension not found in Chrome Preferences")
        
        if enabled:
            criteria_met += 1
            feedback_parts.append("✓ Extension is enabled and loaded as unpacked")
        else:
            if registered:
                if metadata.get('enabled'):
                    feedback_parts.append("⚠ Extension enabled but not loaded as unpacked (wrong installation method)")
                else:
                    feedback_parts.append("✗ Extension is disabled in Chrome")
            else:
                feedback_parts.append("✗ Extension not enabled (not registered)")
        
        # Criterion 5: Name matches (already verified in criterion 1, but count separately)
        if found_ext and valid_manifest and name == "Test Extension":
            criteria_met += 1
            feedback_parts.append(f"✓ Extension name matches: '{name}'")
        else:
            feedback_parts.append("✗ Extension name does not match expected 'Test Extension'")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 80  # Need at least 4/5 criteria
        
        # Build final feedback
        feedback = f"Extension Installation Verification: {criteria_met}/{total_criteria} criteria met\n\n"
        feedback += "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nFinal Score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if passed:
            feedback += f"\n\nExcellent! The Test Extension was successfully loaded as an unpacked extension."
        elif criteria_met >= 3:
            feedback += f"\n\nPartial success. The extension was loaded but some criteria were not met."
        else:
            feedback += f"\n\nTask incomplete. Please ensure you follow all steps to load the unpacked extension."
        
        logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
        
        # Cleanup
        shutil.rmtree(temp_dir)
        cleanup_verification_temp()
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "details": {
                "extension_id": ext_id if found_ext else None,
                "extension_found": found_ext,
                "manifest_valid": valid_manifest,
                "registered": registered,
                "enabled": enabled,
                "metadata": metadata
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "criteria_met": 0,
            "total_criteria": total_criteria
        }
