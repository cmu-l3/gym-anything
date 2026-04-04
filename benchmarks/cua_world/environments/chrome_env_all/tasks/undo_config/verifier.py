#!/usr/bin/env python3
"""
Verifier for Chrome Extension Keyboard Shortcuts Configuration Task
Task: Configure custom keyboard shortcut (Ctrl+Shift+E) for Chrome extension

Verification Strategy:
- Parse Chrome Preferences file (JSON)
- Navigate to extensions.commands section
- Locate the test extension ("Quick Notes") by name/ID
- Verify keyboard shortcut is configured as Ctrl+Shift+E
- Validate shortcut format and binding
"""

import logging
import sys
import os
import json
import tempfile
import re
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

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
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for extension_shortcuts_config@1 task.
    
    Verifies that:
    1. Extension keyboard shortcut is configured in Preferences
    2. Shortcut is set to the expected key combination (Ctrl+Shift+E)
    3. Shortcut format is valid
    4. Shortcut scope is appropriate (in_chrome or global)
    
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
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract preferences and extension commands configuration
        prefs_data, extension_id, error_msg = extract_extension_shortcuts_config(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract preferences: {error_msg}"
            }
        
        # Verify the keyboard shortcut configuration
        result = verify_extension_keyboard_shortcut(
            prefs_data,
            extension_id,
            expected_shortcut="Ctrl+Shift+E",
            expected_command="_execute_action"
        )
        
        # Clean up
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


def extract_extension_shortcuts_config(copy_from_env) -> Tuple[Optional[Dict], Optional[str], str]:
    """
    Extract extension shortcuts configuration from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (preferences_data: dict, extension_id: str, error_message: str)
    """
    temp_file = None
    try:
        # Copy Preferences file from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try primary export location
        try:
            copy_from_env("/tmp/chrome_preferences.json", temp_file.name)
            logger.info("✓ Copied Preferences from /tmp/chrome_preferences.json")
        except Exception as e:
            logger.warning(f"Failed to copy from /tmp: {e}")
            # Try copying directly from Chrome profile
            try:
                copy_from_env("/home/ga/.config/google-chrome-cdp/Default/Preferences", temp_file.name)
                logger.info("✓ Copied Preferences from chrome-cdp profile")
            except Exception as e2:
                # Try alternative profile location
                try:
                    copy_from_env("/home/ga/.config/google-chrome/Default/Preferences", temp_file.name)
                    logger.info("✓ Copied Preferences from standard chrome profile")
                except Exception as e3:
                    return None, None, f"Could not copy Preferences file from any location: {e3}"
        
        # Check file was copied successfully
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return None, None, "Preferences file is empty or does not exist"
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
        
        logger.info("✓ Successfully parsed Preferences JSON")
        
        # Try to identify the extension ID for "Quick Notes"
        extension_id = find_extension_id_by_name(prefs, "Quick Notes")
        
        if not extension_id:
            logger.warning("Could not find 'Quick Notes' extension ID, will search all extensions")
            extension_id = None
        else:
            logger.info(f"✓ Found extension ID: {extension_id}")
        
        return prefs, extension_id, ""
        
    except json.JSONDecodeError as e:
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, None, f"Error extracting preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def find_extension_id_by_name(prefs: Dict, extension_name: str) -> Optional[str]:
    """
    Find extension ID by searching for extension name in Preferences.
    
    Args:
        prefs: Parsed Preferences dictionary
        extension_name: Name of the extension to find
        
    Returns:
        Extension ID string or None if not found
    """
    try:
        # Check extensions.settings for the extension name
        extensions_settings = prefs.get('extensions', {}).get('settings', {})
        
        for ext_id, ext_data in extensions_settings.items():
            # Check manifest.name or path
            manifest = ext_data.get('manifest', {})
            name = manifest.get('name', '')
            
            if extension_name.lower() in name.lower():
                logger.info(f"Found extension '{name}' with ID: {ext_id}")
                return ext_id
        
        # Also check in commands section directly
        commands = prefs.get('extensions', {}).get('commands', {})
        for ext_id in commands.keys():
            # Extension IDs are 32-character lowercase strings
            if len(ext_id) == 32 and ext_id.isalnum():
                # Found a potential match, return first one for now
                logger.info(f"Found extension with commands configured: {ext_id}")
                return ext_id
        
        return None
        
    except Exception as e:
        logger.warning(f"Error finding extension ID: {e}")
        return None


def verify_extension_keyboard_shortcut(
    prefs_data: Dict,
    extension_id: Optional[str],
    expected_shortcut: str,
    expected_command: str
) -> Dict[str, Any]:
    """
    Verify that extension keyboard shortcut is correctly configured.
    
    Args:
        prefs_data: Parsed Preferences dictionary
        extension_id: Target extension ID (or None to search all)
        expected_shortcut: Expected key combination (e.g., "Ctrl+Shift+E")
        expected_command: Expected command name (e.g., "_execute_action")
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    # Navigate to extensions.commands
    commands = prefs_data.get('extensions', {}).get('commands', {})
    
    if not commands:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No extension commands configured. Please navigate to chrome://extensions/shortcuts and configure a keyboard shortcut.",
            "details": {
                "commands_found": False,
                "extension_found": False,
                "shortcut_configured": False,
                "shortcut_correct": False,
                "scope_correct": False
            }
        }
    
    logger.info(f"Found {len(commands)} extension(s) with commands configured")
    
    # Search for the extension (either by ID or by finding any with correct shortcut)
    target_extension_config = None
    found_extension_id = extension_id
    
    if extension_id and extension_id in commands:
        target_extension_config = commands[extension_id]
        logger.info(f"✓ Found configuration for extension ID: {extension_id}")
    else:
        # Search all extensions for one with the expected shortcut
        logger.info("Searching all extensions for configured shortcut...")
        for ext_id, ext_commands in commands.items():
            logger.info(f"Checking extension: {ext_id}")
            for cmd_name, cmd_config in ext_commands.items():
                binding = cmd_config.get('binding', '')
                logger.info(f"  Command '{cmd_name}': binding='{binding}'")
                if binding and normalize_shortcut(binding) == normalize_shortcut(expected_shortcut):
                    target_extension_config = ext_commands
                    found_extension_id = ext_id
                    logger.info(f"✓ Found matching shortcut in extension: {ext_id}")
                    break
            if target_extension_config:
                break
    
    if not target_extension_config:
        # Generate helpful feedback about what was found
        feedback_parts = [
            "Extension shortcut not found or not configured correctly.",
            f"Expected shortcut: {expected_shortcut}",
            "\nExtensions checked:"
        ]
        for ext_id, ext_commands in list(commands.items())[:3]:  # Show first 3
            feedback_parts.append(f"  - {ext_id}: {len(ext_commands)} command(s)")
        
        return {
            "passed": False,
            "score": 25,
            "feedback": "\n".join(feedback_parts),
            "details": {
                "commands_found": True,
                "extension_found": False,
                "shortcut_configured": False,
                "shortcut_correct": False,
                "scope_correct": False,
                "extensions_count": len(commands)
            }
        }
    
    # Check if the expected command exists
    if expected_command not in target_extension_config:
        # Try to find any command with a shortcut
        configured_commands = [
            (cmd, cfg) for cmd, cfg in target_extension_config.items()
            if cfg.get('binding')
        ]
        
        if not configured_commands:
            return {
                "passed": False,
                "score": 50,
                "feedback": f"Extension found but no keyboard shortcuts configured for any command. Please configure '{expected_command}' command.",
                "details": {
                    "commands_found": True,
                    "extension_found": True,
                    "shortcut_configured": False,
                    "shortcut_correct": False,
                    "scope_correct": False
                }
            }
        else:
            # Use the first configured command instead
            expected_command, command_config = configured_commands[0]
            logger.info(f"Using configured command: {expected_command}")
    else:
        command_config = target_extension_config[expected_command]
    
    # Extract shortcut configuration
    assigned_shortcut = command_config.get('binding', '')
    is_global = command_config.get('global', False)
    
    logger.info(f"Command configuration:")
    logger.info(f"  Assigned shortcut: {assigned_shortcut}")
    logger.info(f"  Global scope: {is_global}")
    
    # Validate shortcut
    if not assigned_shortcut:
        return {
            "passed": False,
            "score": 50,
            "feedback": f"Command '{expected_command}' found but no keyboard shortcut assigned. Shortcut field is empty.",
            "details": {
                "commands_found": True,
                "extension_found": True,
                "shortcut_configured": False,
                "shortcut_correct": False,
                "scope_correct": False
            }
        }
    
    # Check if shortcut matches expected (with normalization)
    shortcut_correct = (normalize_shortcut(assigned_shortcut) == normalize_shortcut(expected_shortcut))
    
    # Check scope (prefer in_chrome for predictability, but global is acceptable)
    scope_correct = not is_global  # in_chrome (False) is preferred
    scope_acceptable = True  # Both are acceptable
    
    # Validate shortcut format
    format_valid = validate_shortcut_format(assigned_shortcut)
    
    # Calculate score based on criteria
    criteria = {
        "commands_found": True,
        "extension_found": True,
        "shortcut_configured": True,
        "shortcut_correct": shortcut_correct,
        "scope_optimal": scope_correct,
        "format_valid": format_valid
    }
    
    # Scoring logic
    if shortcut_correct and format_valid:
        if scope_correct:
            score = 100
            feedback = f"✅ Perfect! Keyboard shortcut correctly configured as '{assigned_shortcut}' with optimal 'In Chrome' scope."
        else:
            score = 90
            feedback = f"✅ Keyboard shortcut correctly configured as '{assigned_shortcut}', but set to 'Global' scope (minor issue)."
    elif normalize_shortcut(assigned_shortcut).replace('ctrl', '').replace('shift', '').replace('alt', '') == 'e':
        # Has 'E' key but wrong modifiers
        score = 75
        feedback = f"⚠ Shortcut configured as '{assigned_shortcut}' uses correct key (E) but different modifiers. Expected: {expected_shortcut}"
    elif assigned_shortcut:
        score = 60
        feedback = f"⚠ Shortcut configured as '{assigned_shortcut}' but does not match expected '{expected_shortcut}'."
    else:
        score = 50
        feedback = "❌ Shortcut field is empty or not saved."
    
    passed = score >= 75
    
    # Add detailed information to feedback
    feedback += f"\n\nDetails:"
    feedback += f"\n  - Extension ID: {found_extension_id}"
    feedback += f"\n  - Command: {expected_command}"
    feedback += f"\n  - Assigned shortcut: {assigned_shortcut}"
    feedback += f"\n  - Expected shortcut: {expected_shortcut}"
    feedback += f"\n  - Scope: {'Global' if is_global else 'In Chrome'}"
    feedback += f"\n  - Format valid: {format_valid}"
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": {
            **criteria,
            "assigned_shortcut": assigned_shortcut,
            "expected_shortcut": expected_shortcut,
            "is_global": is_global,
            "extension_id": found_extension_id,
            "command": expected_command
        }
    }


def normalize_shortcut(shortcut: str) -> str:
    """
    Normalize shortcut string for comparison.
    
    Args:
        shortcut: Keyboard shortcut string (e.g., "Ctrl+Shift+E")
        
    Returns:
        Normalized lowercase string with consistent separator
    """
    if not shortcut:
        return ""
    
    # Convert to lowercase and standardize separators
    normalized = shortcut.lower().replace(' ', '').replace('_', '+')
    
    # Sort modifiers alphabetically for consistent comparison
    parts = normalized.split('+')
    if len(parts) > 1:
        modifiers = sorted(parts[:-1])  # Sort all but last (the key)
        key = parts[-1]
        normalized = '+'.join(modifiers + [key])
    
    return normalized


def validate_shortcut_format(shortcut: str) -> bool:
    """
    Validate that shortcut follows Chrome's format requirements.
    
    Args:
        shortcut: Keyboard shortcut string
        
    Returns:
        True if valid format, False otherwise
    """
    if not shortcut:
        return False
    
    # Chrome shortcut format: Modifier+Modifier+Key
    # Valid modifiers: Ctrl, Alt, Shift, Command (Mac), Search (ChromeOS)
    # Valid keys: A-Z, 0-9, F1-F12, special keys
    
    parts = shortcut.split('+')
    
    if len(parts) < 2:
        return False  # Must have at least one modifier + one key
    
    modifiers = parts[:-1]
    key = parts[-1]
    
    valid_modifiers = ['ctrl', 'alt', 'shift', 'command', 'search']
    
    # Check modifiers
    for mod in modifiers:
        if mod.lower() not in valid_modifiers:
            return False
    
    # Check key (simple validation)
    if not key or len(key) > 10:  # Reasonable length check
        return False
    
    return True
