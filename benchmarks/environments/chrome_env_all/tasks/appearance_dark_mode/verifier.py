#!/usr/bin/env python3
"""
Verifier for Chrome Appearance Dark Mode Configuration Task (appearance_dark_mode@1)
Task: Enable dark mode in Chrome's appearance settings

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract theme settings from multiple possible locations
- Verify that dark mode is explicitly enabled (not just System default)
- Award bonus points for additional appearance customizations
- Ensure configuration is valid and properly persisted

Scoring:
- 100%: Dark mode enabled with additional appearance customizations
- 85-99%: Dark mode enabled, some additional settings configured
- 75-84%: Dark mode enabled with valid configuration (minimum to pass)
- 50-74%: Dark mode partially configured or using System theme
- 0-49%: Dark mode not enabled or preferences not updated
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../..', 'utils'))
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
    
    def parse_preferences(path):
        """Fallback preferences parser"""
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for appearance_dark_mode@1.
    
    Verifies that Chrome's dark mode has been enabled through appearance settings.
    
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
        # Extract theme configuration from Chrome Preferences
        prefs_data, error_msg = extract_preferences_from_container(copy_from_env)
        
        if prefs_data is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome preferences: {error_msg}"
            }
        
        # Verify dark mode configuration
        verification_result = verify_dark_mode_configuration(prefs_data)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_preferences_from_container(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract Chrome Preferences file from container.
    
    Tries multiple possible locations and methods to retrieve the Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (preferences_dict or None, error_message)
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
                prefs_data = parse_preferences(prefs_path)
                logger.info("✓ Successfully retrieved Preferences using utilities")
                return prefs_data, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying manual fallback")
        
        # Fallback: Manual extraction from multiple possible locations
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_file.close()
        temp_path = temp_file.name
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_export.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 0:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    
                    logger.info(f"✓ Successfully copied Preferences from: {container_path}")
                    return prefs_data, ""
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        return None, "Could not access Preferences file from any known location"
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting preferences: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def detect_dark_mode(prefs: Dict[str, Any]) -> Tuple[bool, str, int]:
    """
    Detect if dark mode is enabled in Chrome preferences.
    
    Checks multiple possible locations where theme settings might be stored:
    - browser.theme.color_scheme (primary method for modern Chrome)
    - ntp theme settings (legacy or alternative method)
    - extensions.theme settings (custom theme indication)
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Tuple of (is_dark_enabled: bool, detection_method: str, confidence: int 0-100)
    """
    # Method 1: Check explicit browser.theme.color_scheme setting
    # This is the primary and most reliable method
    browser_theme = prefs.get('browser', {}).get('theme', {})
    color_scheme = browser_theme.get('color_scheme')
    
    logger.info(f"Checking browser.theme.color_scheme: {color_scheme}")
    
    # color_scheme values: 0=System, 1=Light, 2=Dark, 3=GTK+ (Linux)
    if color_scheme == 2:
        return True, "Explicit dark mode setting (browser.theme.color_scheme=2)", 100
    
    # Check if System theme is selected (not ideal, as we want explicit Dark)
    if color_scheme == 0:
        logger.warning("System theme detected (color_scheme=0), not explicit dark mode")
        return False, "System theme selected (not explicit dark mode)", 0
    
    # Check if Light theme is selected
    if color_scheme == 1:
        logger.info("Light theme explicitly selected (color_scheme=1)")
        return False, "Light theme selected", 0
    
    # Method 2: Check for dark theme via GTK+ system integration (Linux)
    if color_scheme == 3:
        logger.info("GTK+ system theme detected (color_scheme=3)")
        # This might be dark, but we can't be certain without system inspection
        # We'll accept it with lower confidence
        return True, "GTK+ system theme (may be dark)", 60
    
    # Method 3: Check NTP (New Tab Page) theme settings
    ntp_settings = prefs.get('ntp', {})
    custom_bg_dict = ntp_settings.get('custom_background_dict', {})
    
    # Check for dark mode indicator in NTP settings
    if custom_bg_dict.get('color_dark_mode'):
        logger.info("Dark mode detected via NTP custom_background_dict")
        return True, "Dark mode via NTP custom background settings", 70
    
    # Check background color for darkness
    bg_color = ntp_settings.get('theme_background_color', '')
    if bg_color and is_dark_color(bg_color):
        logger.info(f"Dark background color detected in NTP: {bg_color}")
        return True, f"Dark theme detected via NTP background color ({bg_color})", 70
    
    # Method 4: Check for installed dark theme extension
    extensions_theme = prefs.get('extensions', {}).get('theme', {})
    theme_id = extensions_theme.get('id', '')
    theme_name = extensions_theme.get('name', '')
    
    if theme_id and 'dark' in theme_id.lower():
        logger.info(f"Dark theme extension detected: {theme_id}")
        return True, f"Dark theme extension ({theme_id})", 80
    
    if theme_name and 'dark' in theme_name.lower():
        logger.info(f"Dark theme extension detected by name: {theme_name}")
        return True, f"Dark theme extension ({theme_name})", 80
    
    # Method 5: Check profile theme metadata
    profile_theme = prefs.get('profile', {}).get('theme', {})
    if profile_theme.get('is_dark'):
        logger.info("Dark theme detected via profile metadata")
        return True, "Dark theme via profile metadata", 75
    
    # No dark mode detected
    if color_scheme is None:
        return False, "No theme setting found (default light mode)", 0
    
    return False, f"No dark mode detected (color_scheme={color_scheme})", 0


def is_dark_color(color_str: str) -> bool:
    """
    Check if a color string represents a dark color.
    
    Handles various color formats: hex, rgb, rgba, named colors
    
    Args:
        color_str: Color string in various formats
        
    Returns:
        bool: True if color is dark (low brightness)
    """
    try:
        color_str = color_str.strip().lower()
        
        # Handle hex colors (#RRGGBB or #RGB)
        if color_str.startswith('#'):
            color_str = color_str[1:]
            if len(color_str) == 3:
                color_str = ''.join([c*2 for c in color_str])
            
            r = int(color_str[0:2], 16)
            g = int(color_str[2:4], 16)
            b = int(color_str[4:6], 16)
            
            # Calculate perceived brightness (using standard formula)
            brightness = (0.299 * r + 0.587 * g + 0.114 * b)
            return brightness < 100  # Dark if brightness < ~40% of max (255)
        
        # Handle rgb/rgba format
        if color_str.startswith('rgb'):
            # Extract numbers from rgb(r, g, b) or rgba(r, g, b, a)
            import re
            numbers = re.findall(r'\d+', color_str)
            if len(numbers) >= 3:
                r, g, b = int(numbers[0]), int(numbers[1]), int(numbers[2])
                brightness = (0.299 * r + 0.587 * g + 0.114 * b)
                return brightness < 100
        
        # For other formats or named colors, we can't determine reliably
        return False
        
    except Exception as e:
        logger.debug(f"Could not parse color '{color_str}': {e}")
        return False


def check_additional_appearance_settings(prefs: Dict[str, Any]) -> Tuple[int, list]:
    """
    Check for additional appearance customizations that enhance dark mode experience.
    
    Awards bonus points for:
    - Show home button enabled
    - Show bookmarks bar enabled
    - Custom font settings (shows exploration of appearance options)
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Tuple of (bonus_points: int, features_list: list of str)
    """
    bonus_points = 0
    features = []
    
    # Check if home button is enabled
    show_home_button = prefs.get('browser', {}).get('show_home_button', False)
    if show_home_button:
        bonus_points += 10
        features.append("Home button enabled")
        logger.info("✓ Additional setting: Show home button enabled")
    
    # Check if bookmarks bar is enabled
    bookmark_bar = prefs.get('bookmark_bar', {})
    show_bookmarks = bookmark_bar.get('show_on_all_tabs', False)
    if show_bookmarks:
        bonus_points += 10
        features.append("Bookmarks bar enabled")
        logger.info("✓ Additional setting: Bookmarks bar enabled")
    
    # Check if custom font settings were modified (indicates exploration)
    webkit_prefs = prefs.get('webkit', {}).get('webprefs', {})
    default_font_size = webkit_prefs.get('default_font_size', 16)
    if default_font_size != 16:  # 16 is default
        bonus_points += 5
        features.append(f"Custom font size ({default_font_size}px)")
        logger.info(f"✓ Additional setting: Custom font size ({default_font_size}px)")
    
    # Check for custom font families (shows deeper customization)
    font_family_map = webkit_prefs.get('standard_font_family_map', {})
    if font_family_map and len(font_family_map) > 0:
        bonus_points += 5
        features.append("Custom fonts configured")
        logger.info("✓ Additional setting: Custom font families")
    
    return bonus_points, features


def verify_dark_mode_configuration(prefs: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main verification logic for dark mode configuration.
    
    Performs multi-criteria verification:
    1. Dark mode is enabled (required)
    2. Configuration is explicit (not just System default)
    3. Settings are valid and well-formed
    4. Bonus points for additional appearance customizations
    
    Args:
        prefs: Parsed Chrome Preferences dictionary
        
    Returns:
        Verification result dict with passed, score, feedback, and details
    """
    if not prefs:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse Chrome preferences file"
        }
    
    # Check if dark mode is enabled
    is_dark, detection_method, confidence = detect_dark_mode(prefs)
    
    logger.info(f"Dark mode detection: enabled={is_dark}, method='{detection_method}', confidence={confidence}")
    
    if not is_dark:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Dark mode not enabled. {detection_method}. "
                       f"Please navigate to chrome://settings/appearance and select 'Dark' from the Theme dropdown.",
            "details": {
                "dark_mode_enabled": False,
                "detection_method": detection_method,
                "confidence": confidence
            }
        }
    
    # Dark mode is enabled - calculate score based on confidence and additional settings
    base_score = 75  # Minimum passing score for dark mode enabled
    
    # Adjust base score based on detection confidence
    if confidence == 100:
        base_score = 75  # Perfect explicit dark mode setting
    elif confidence >= 70:
        base_score = 70  # Good confidence, but not perfect
    else:
        base_score = 60  # Lower confidence (e.g., GTK+ theme)
    
    # Check for additional appearance customizations
    bonus_points, additional_features = check_additional_appearance_settings(prefs)
    
    # Calculate final score
    total_score = min(100, base_score + bonus_points)
    
    # Determine pass/fail
    passed = total_score >= 75
    
    # Generate detailed feedback
    feedback_parts = []
    feedback_parts.append(f"✓ Dark mode enabled: {detection_method}")
    
    if additional_features:
        feedback_parts.append(f"✓ Additional customizations: {', '.join(additional_features)} (+{bonus_points} points)")
    else:
        feedback_parts.append("ℹ No additional appearance customizations detected")
    
    feedback_parts.append(f"Final score: {total_score}/100")
    
    if passed:
        if total_score == 100:
            feedback_parts.append("🌟 Perfect! Dark mode enabled with excellent appearance customization!")
        elif total_score >= 90:
            feedback_parts.append("✅ Excellent! Dark mode enabled with good customization!")
        else:
            feedback_parts.append("✅ Task completed successfully!")
    else:
        feedback_parts.append("⚠ Task incomplete: Dark mode detection confidence too low or settings not properly configured")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={total_score}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback,
        "details": {
            "dark_mode_enabled": is_dark,
            "detection_method": detection_method,
            "confidence": confidence,
            "base_score": base_score,
            "bonus_points": bonus_points,
            "additional_features": additional_features
        }
    }
