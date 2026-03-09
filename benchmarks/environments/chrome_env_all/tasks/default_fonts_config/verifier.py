#!/usr/bin/env python3
"""
Verifier for Chrome Default Font Customization Task (default_fonts_config@1)
Task: Customize Chrome's default font families (Standard, Serif, Sans-serif)

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse webkit.webprefs.fonts section
- Check that standard.Zyyy, serif.Zyyy, and sansserif.Zyyy were modified
- Validate fonts differ from Chrome defaults
- Verify selected fonts are valid system fonts
- Provide detailed feedback on each font family change
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        cleanup_verification_temp
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


# Common valid Linux system fonts
VALID_SYSTEM_FONTS = {
    # Sans-serif fonts
    'Liberation Sans', 'DejaVu Sans', 'Ubuntu', 'Ubuntu Condensed',
    'Noto Sans', 'Roboto', 'Droid Sans', 'FreeSans', 'Cantarell',
    'Open Sans', 'Arimo', 'PT Sans',
    
    # Serif fonts
    'Liberation Serif', 'DejaVu Serif', 'Noto Serif', 'FreeSerif',
    'Droid Serif', 'Tinos', 'PT Serif', 'Georgia',
    
    # Monospace fonts (for completeness)
    'Liberation Mono', 'DejaVu Sans Mono', 'Ubuntu Mono',
    'Noto Sans Mono', 'FreeMono', 'Droid Sans Mono', 'Cousine',
    
    # Common system fonts
    'Arial', 'Helvetica', 'Times New Roman', 'Times', 'Courier New',
    'Verdana', 'Trebuchet MS', 'Comic Sans MS'
}

# Chrome default fonts (what we expect to be changed FROM)
CHROME_DEFAULT_FONTS = {
    'standard': ['Times New Roman', 'Times', 'serif', 'Times', 'DejaVu Serif'],
    'serif': ['Times New Roman', 'Times', 'serif', 'Times', 'DejaVu Serif'],
    'sansserif': ['Arial', 'Helvetica', 'sans-serif', 'DejaVu Sans']
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for default_fonts_config@1.
    
    Verifies that Chrome's default font families (Standard, Serif, Sans-serif)
    have been customized from their default values.
    
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
        # Extract font settings from Chrome Preferences
        font_settings, error_msg = extract_font_settings(copy_from_env)
        
        if font_settings is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract font settings: {error_msg}"
            }
        
        # Verify font customization
        verification_result = verify_font_customization(font_settings)
        
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


def extract_font_settings(copy_from_env) -> Tuple[Optional[Dict], str]:
    """
    Extract font settings from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (font_settings_dict or None, error_message)
    """
    temp_file = None
    try:
        # Create temporary file for Preferences
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
        temp_path = temp_file.name
        temp_file.close()
        
        # Try multiple possible locations for Preferences file
        possible_paths = [
            "/tmp/chrome_preferences_fonts.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_path)
                
                # Check if file was copied successfully
                if os.path.exists(temp_path) and os.path.getsize(temp_path) > 100:
                    with open(temp_path, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed Preferences from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, "Could not copy or parse Preferences file from any known location"
        
        # Navigate to font settings in the nested structure
        # Path: webkit -> webprefs -> fonts
        webkit = prefs_data.get('webkit', {})
        if not webkit:
            return None, "No 'webkit' section found in Preferences"
        
        webprefs = webkit.get('webprefs', {})
        if not webprefs:
            return None, "No 'webprefs' section found in webkit preferences"
        
        fonts = webprefs.get('fonts', {})
        if not fonts:
            return None, "No 'fonts' section found in webkit.webprefs"
        
        # Extract font families for the default script (Zyyy = Common script code)
        standard_fonts = fonts.get('standard', {})
        serif_fonts = fonts.get('serif', {})
        sansserif_fonts = fonts.get('sansserif', {})
        
        font_settings = {
            'standard': standard_fonts.get('Zyyy', None),
            'serif': serif_fonts.get('Zyyy', None),
            'sansserif': sansserif_fonts.get('Zyyy', None)
        }
        
        logger.info(f"Extracted font settings:")
        logger.info(f"  Standard font: {font_settings['standard']}")
        logger.info(f"  Serif font: {font_settings['serif']}")
        logger.info(f"  Sans-serif font: {font_settings['sansserif']}")
        
        return font_settings, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Error extracting font settings: {e}", exc_info=True)
        return None, f"Error extracting font settings: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass


def is_font_changed_from_default(font_name: Optional[str], font_type: str) -> bool:
    """
    Check if a font has been changed from Chrome's default.
    
    Args:
        font_name: Current font name
        font_type: Type of font ('standard', 'serif', 'sansserif')
        
    Returns:
        True if font differs from defaults
    """
    if font_name is None:
        return False
    
    defaults = CHROME_DEFAULT_FONTS.get(font_type, [])
    
    # Check if current font is in the default list
    return font_name not in defaults


def is_valid_system_font(font_name: Optional[str]) -> bool:
    """
    Check if a font name is a valid system font.
    
    Args:
        font_name: Font name to check
        
    Returns:
        True if font is recognized as valid
    """
    if font_name is None or font_name == "":
        return False
    
    # Direct match
    if font_name in VALID_SYSTEM_FONTS:
        return True
    
    # Check if any known font is substring of the font name
    # (handles variations like "Liberation Sans Bold")
    for valid_font in VALID_SYSTEM_FONTS:
        if valid_font in font_name:
            return True
    
    # If font name contains common font family keywords, accept it
    font_lower = font_name.lower()
    common_keywords = ['sans', 'serif', 'mono', 'liberation', 'dejavu', 'ubuntu', 'noto', 'roboto']
    if any(keyword in font_lower for keyword in common_keywords):
        return True
    
    return False


def verify_font_customization(font_settings: Dict[str, Optional[str]]) -> Dict[str, Any]:
    """
    Verify that font customization was performed correctly.
    
    Checks:
    1. Standard font was changed from default
    2. Serif font was changed from default
    3. Sans-serif font was changed from default
    4. All selected fonts are valid system fonts
    
    Args:
        font_settings: Dict with 'standard', 'serif', 'sansserif' font names
        
    Returns:
        Verification result with passed, score, and feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    standard_font = font_settings.get('standard')
    serif_font = font_settings.get('serif')
    sansserif_font = font_settings.get('sansserif')
    
    # Criterion 1: Standard font modified
    standard_changed = is_font_changed_from_default(standard_font, 'standard')
    if standard_changed:
        criteria_met += 1
        feedback_parts.append(f"✓ Standard font changed: {standard_font}")
    else:
        default_hint = ", ".join(CHROME_DEFAULT_FONTS['standard'][:3])
        feedback_parts.append(f"✗ Standard font not changed (current: {standard_font}, defaults: {default_hint})")
    
    # Criterion 2: Serif font modified
    serif_changed = is_font_changed_from_default(serif_font, 'serif')
    if serif_changed:
        criteria_met += 1
        feedback_parts.append(f"✓ Serif font changed: {serif_font}")
    else:
        default_hint = ", ".join(CHROME_DEFAULT_FONTS['serif'][:3])
        feedback_parts.append(f"✗ Serif font not changed (current: {serif_font}, defaults: {default_hint})")
    
    # Criterion 3: Sans-serif font modified
    sansserif_changed = is_font_changed_from_default(sansserif_font, 'sansserif')
    if sansserif_changed:
        criteria_met += 1
        feedback_parts.append(f"✓ Sans-serif font changed: {sansserif_font}")
    else:
        default_hint = ", ".join(CHROME_DEFAULT_FONTS['sansserif'][:3])
        feedback_parts.append(f"✗ Sans-serif font not changed (current: {sansserif_font}, defaults: {default_hint})")
    
    # Criterion 4: All fonts are valid
    all_valid = True
    invalid_fonts = []
    
    if standard_changed:
        if not is_valid_system_font(standard_font):
            all_valid = False
            invalid_fonts.append(f"Standard: {standard_font}")
    
    if serif_changed:
        if not is_valid_system_font(serif_font):
            all_valid = False
            invalid_fonts.append(f"Serif: {serif_font}")
    
    if sansserif_changed:
        if not is_valid_system_font(sansserif_font):
            all_valid = False
            invalid_fonts.append(f"Sans-serif: {sansserif_font}")
    
    if all_valid and (standard_changed or serif_changed or sansserif_changed):
        criteria_met += 1
        feedback_parts.append("✓ All changed fonts are valid system fonts")
    elif not all_valid:
        feedback_parts.append(f"⚠ Unrecognized fonts: {'; '.join(invalid_fonts)}")
    else:
        feedback_parts.append("✗ No fonts were changed to validate")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build comprehensive feedback
    feedback = "Font Customization Verification Results:\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTo pass this task:"
        feedback += "\n  1. Navigate to chrome://settings/fonts"
        feedback += "\n  2. Change Standard font dropdown to a different font"
        feedback += "\n  3. Change Serif font dropdown to a different font"
        feedback += "\n  4. Change Sans-serif font dropdown to a different font"
        feedback += "\n\nCommon valid fonts: Liberation Sans, DejaVu Sans, Liberation Serif, etc."
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "standard_font": standard_font,
            "serif_font": serif_font,
            "sansserif_font": sansserif_font,
            "standard_changed": standard_changed,
            "serif_changed": serif_changed,
            "sansserif_changed": sansserif_changed,
            "all_valid": all_valid,
            "criteria_met": criteria_met
        }
    }
