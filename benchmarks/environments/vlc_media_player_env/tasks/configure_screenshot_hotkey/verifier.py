#!/usr/bin/env python3
"""
Verifier for Configure Screenshot Hotkey task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_config(config_path):
    """
    Parse VLC configuration file and extract key-value pairs.
    
    Args:
        config_path: Path to vlcrc file
        
    Returns:
        Dict of config parameters
    """
    config = {}
    
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments, empty lines, and section headers
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                
                # Parse key=value pairs
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
        
        return config
        
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
        return {}


def is_valid_vlc_hotkey(hotkey):
    """
    Validate VLC hotkey format.
    
    Valid formats:
    - Single key: "a", "F8", "Space"
    - With modifiers: "Ctrl+p", "Shift+F1", "Alt+Ctrl+a"
    
    Args:
        hotkey: Hotkey string
        
    Returns:
        True if valid format, False otherwise
    """
    if not hotkey or hotkey == "":
        return False
    
    # Valid VLC modifiers (case-insensitive)
    valid_modifiers = {
        'ctrl', 'alt', 'shift', 'command', 'meta',
        'Ctrl', 'Alt', 'Shift', 'Command', 'Meta'
    }
    
    # Valid special key names
    valid_special_keys = {
        'Space', 'Enter', 'Tab', 'Backspace', 'Esc', 'Escape',
        'Insert', 'Delete', 'Home', 'End', 'PageUp', 'PageDown',
        'Up', 'Down', 'Left', 'Right',
        'space', 'enter', 'tab', 'backspace', 'esc', 'escape',
        'insert', 'delete', 'home', 'end', 'pageup', 'pagedown',
        'up', 'down', 'left', 'right'
    }
    
    # Split by '+' to get components
    parts = hotkey.split('+')
    
    if len(parts) == 0:
        return False
    
    # Check each part
    for i, part in enumerate(parts):
        is_last = (i == len(parts) - 1)
        
        if is_last:
            # Last part should be the actual key
            # Check if it's a single letter
            if len(part) == 1 and part.isalpha():
                continue
            # Check if it's an F-key (F1-F24)
            if re.match(r'^F\d{1,2}$', part, re.IGNORECASE):
                continue
            # Check if it's a special key name
            if part in valid_special_keys:
                continue
            # Check if it's a number
            if part.isdigit() and len(part) == 1:
                continue
            # Invalid final key
            return False
        else:
            # Non-last parts should be modifiers
            if part not in valid_modifiers:
                return False
    
    return True


def get_snapshot_hotkey_from_config(config):
    """
    Extract snapshot hotkey from VLC config.
    
    Args:
        config: Parsed VLC config dict
        
    Returns:
        Tuple of (hotkey_value, parameter_name) or (None, None)
    """
    # Check various possible parameter names
    hotkey_params = [
        'key-snapshot',
        'global-key-snapshot',
        'key-take-video-snapshot'
    ]
    
    for param in hotkey_params:
        if param in config:
            value = config[param]
            if value:  # Non-empty
                return value, param
    
    return None, None


def verify_configure_screenshot_hotkey(traj, env_info, task_info):
    """
    Verify configure screenshot hotkey task completion.
    
    Checks:
    1. VLC config file accessible and parseable
    2. Snapshot hotkey was changed from default
    3. New hotkey is in valid format
    
    Scoring:
    - Config accessible: +1 criterion
    - Hotkey changed from default: +1 criterion
    - Valid hotkey format: +1 criterion
    
    Pass threshold: 75% (2/3 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Known default values for VLC snapshot hotkey
    default_values = [
        'Shift+s', 's', 'Shift+S', 'S', 
        '', 'Unset', 'unset'
    ]
    
    # Copy VLC config file from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # Copy config file
        try:
            copy_from_env("/tmp/vlc_hotkey_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying config file: {e}")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Could not access VLC config file: {str(e)}"
            }
        
        # Parse config file
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file is empty or could not be parsed"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Extract snapshot hotkey
        hotkey_value, param_name = get_snapshot_hotkey_from_config(config)
        
        if hotkey_value is None:
            # No hotkey found at all
            feedback_parts.append("❌ No snapshot hotkey found in config")
            os.unlink(temp_config.name)
            
            score = int((criteria_met / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check if hotkey differs from default
        is_default = hotkey_value in default_values
        
        if not is_default:
            criteria_met += 1
            feedback_parts.append(f"✅ Hotkey changed from default to: {hotkey_value}")
        else:
            feedback_parts.append(f"❌ Hotkey still at default value: {hotkey_value}")
        
        # Validate hotkey format
        if is_valid_vlc_hotkey(hotkey_value):
            criteria_met += 1
            feedback_parts.append(f"✅ Valid hotkey format")
        else:
            feedback_parts.append(f"⚠️ Hotkey format may be invalid: {hotkey_value}")
        
        # Cleanup
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Check completion marker (optional bonus)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_hotkey_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        # Completion marker is optional, don't penalize
        pass
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }