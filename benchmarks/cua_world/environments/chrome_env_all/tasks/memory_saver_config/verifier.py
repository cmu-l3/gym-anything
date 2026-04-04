#!/usr/bin/env python3
"""
Verifier for Chrome Memory Saver Configuration Task (memory_saver_config@1)
Task: Enable Memory Saver mode in Chrome's performance settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract Memory Saver configuration
- Check multiple possible JSON paths (Chrome versions vary)
- Validate that Memory Saver is explicitly enabled
- Ensure configuration was persisted correctly
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
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for memory_saver_config@1.
    
    Verifies that Chrome's Memory Saver mode has been enabled in performance settings.
    
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
            "feedback": "Copy function not available in environment - cannot verify task"
        }

    try:
        # Extract Memory Saver configuration from Preferences
        memory_saver_enabled, state_value, json_path, error_msg = extract_memory_saver_config(copy_from_env)
        
        if memory_saver_enabled is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract Memory Saver configuration: {error_msg}"
            }
        
        # Validate configuration
        is_valid, score, feedback = validate_memory_saver_config(
            memory_saver_enabled, 
            state_value, 
            json_path
        )
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "memory_saver_enabled": memory_saver_enabled,
                "state_value": state_value,
                "config_path": json_path
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


def extract_memory_saver_config(copy_from_env) -> Tuple[Optional[bool], Any, str, str]:
    """
    Extract Memory Saver configuration from Chrome Preferences file.
    
    Chrome stores Memory Saver settings in various locations depending on version:
    - performance_tuning.high_efficiency_mode.state (Chrome 108+)
    - performance_tuning.high_efficiency_mode.enabled (some versions)
    - performance_tuning.battery_saver_mode_state (related feature)
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (enabled: bool or None, state_value: any, json_path: str, error_message: str)
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
                cleanup_verification_temp()
                
                # Check multiple possible paths
                enabled, value, path = check_memory_saver_in_prefs(prefs)
                if enabled is not None:
                    return enabled, value, path, ""
                else:
                    return None, None, "", "Memory Saver configuration not found in Preferences"
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        preferences_paths = [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_path = None
        
        for container_path in preferences_paths:
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
            return None, None, "", "Could not access Preferences file from any known location"
        
        # Check for Memory Saver configuration in parsed preferences
        enabled, value, path = check_memory_saver_in_prefs(prefs)
        
        if enabled is not None:
            logger.info(f"Memory Saver found: enabled={enabled}, value={value}, path={path}")
            return enabled, value, path, ""
        else:
            return None, None, "", "Memory Saver configuration not found in Preferences"
        
    except json.JSONDecodeError as e:
        return None, None, "", f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, None, "", f"Error extracting Memory Saver config: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def check_memory_saver_in_prefs(prefs: Dict[str, Any]) -> Tuple[Optional[bool], Any, str]:
    """
    Check for Memory Saver configuration in Chrome Preferences JSON.
    
    Tries multiple possible paths and value formats across Chrome versions.
    
    Args:
        prefs: Parsed Chrome Preferences JSON
        
    Returns:
        Tuple of (enabled: bool or None, value: any, json_path: str)
    """
    # Define possible configuration paths and their "enabled" values
    # Format: (json_path_list, enabled_values, disabled_values)
    config_checks = [
        # Chrome 108+ primary path
        (
            ['performance_tuning', 'high_efficiency_mode', 'state'],
            [1, 2, True, 'enabled', 'on'],  # Values indicating enabled
            [0, False, 'disabled', 'off']    # Values indicating disabled
        ),
        # Alternative enabled field
        (
            ['performance_tuning', 'high_efficiency_mode', 'enabled'],
            [True, 1, 'true'],
            [False, 0, 'false']
        ),
        # Battery saver mode state (related feature)
        (
            ['performance_tuning', 'battery_saver_mode_state'],
            [1, 2, True],
            [0, False]
        ),
        # Top-level alternative (some Chrome versions)
        (
            ['high_efficiency_mode_enabled'],
            [True, 1],
            [False, 0]
        ),
    ]
    
    for path_keys, enabled_values, disabled_values in config_checks:
        value = get_nested_value(prefs, path_keys)
        
        if value is not None:
            path_str = '.'.join(path_keys)
            logger.info(f"Found value at {path_str}: {value}")
            
            # Check if value indicates enabled
            if value in enabled_values:
                return True, value, path_str
            elif value in disabled_values:
                return False, value, path_str
            else:
                # Found the key but value is unexpected
                logger.warning(f"Unexpected value {value} at {path_str}")
                # Treat as disabled if not in enabled list
                return False, value, path_str
    
    # Configuration not found at any known path
    return None, None, ""


def get_nested_value(data: Dict[str, Any], path: list) -> Any:
    """
    Safely navigate nested dictionary structure.
    
    Args:
        data: Dictionary to navigate
        path: List of keys to follow
        
    Returns:
        Value at path, or None if path doesn't exist
    """
    current = data
    for key in path:
        if isinstance(current, dict) and key in current:
            current = current[key]
        else:
            return None
    return current


def validate_memory_saver_config(enabled: bool, state_value: Any, json_path: str) -> Tuple[bool, int, str]:
    """
    Validate that Memory Saver configuration is correct.
    
    Args:
        enabled: Whether Memory Saver is enabled
        state_value: Raw value from Preferences
        json_path: JSON path where configuration was found
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    feedback_parts = []
    
    # Criterion 1: Configuration exists and was found
    feedback_parts.append(f"✓ Memory Saver configuration found at: {json_path}")
    
    # Criterion 2: Memory Saver is enabled
    if enabled:
        feedback_parts.append(f"✓ Memory Saver is ENABLED (value: {state_value})")
    else:
        feedback_parts.append(f"✗ Memory Saver is DISABLED (value: {state_value})")
    
    # Criterion 3: Configuration was persisted properly
    feedback_parts.append(f"✓ Configuration properly persisted to Preferences file")
    
    # Criterion 4: Valid configuration path (sanity check)
    known_paths = [
        'performance_tuning.high_efficiency_mode.state',
        'performance_tuning.high_efficiency_mode.enabled',
        'performance_tuning.battery_saver_mode_state',
        'high_efficiency_mode_enabled'
    ]
    if json_path in known_paths:
        feedback_parts.append(f"✓ Configuration path is valid for Chrome settings")
    else:
        feedback_parts.append(f"⚠ Configuration found at non-standard path: {json_path}")
    
    # Calculate score and determine pass/fail
    if not enabled:
        score = 0
        feedback_parts.append("")
        feedback_parts.append("=" * 50)
        feedback_parts.append("❌ TASK FAILED: Memory Saver is not enabled")
        feedback_parts.append("")
        feedback_parts.append("The configuration was found but Memory Saver mode is disabled.")
        feedback_parts.append("Please navigate to chrome://settings/performance and toggle Memory Saver ON.")
        is_valid = False
    else:
        score = 100
        feedback_parts.append("")
        feedback_parts.append("=" * 50)
        feedback_parts.append("✅ TASK COMPLETED SUCCESSFULLY!")
        feedback_parts.append("")
        feedback_parts.append("Memory Saver mode has been enabled in Chrome's performance settings.")
        feedback_parts.append("This will help reduce memory usage from inactive tabs.")
        is_valid = True
    
    feedback = "\n".join(feedback_parts)
    
    return is_valid, score, feedback
