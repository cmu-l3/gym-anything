#!/usr/bin/env python3
"""
Verifier for Chrome Font Family Customization Task (font_family_config@1)
Task: Customize Chrome's font families for different text types

Expected configuration:
- Standard font: Times New Roman
- Serif font: Georgia
- Sans-serif font: Arial
- Fixed-width font: Courier New

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract webkit.webprefs.fonts structure
- Validate that all 4 font families are set
- Check fonts differ from Chrome defaults
- Verify fonts match expected values (with flexibility for case/spacing)
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
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


# Chrome default fonts (typical values)
DEFAULT_FONTS = {
    'standard': 'Times New Roman',
    'serif': 'Times New Roman',
    'sansserif': 'Arial',
    'fixed': 'Consolas'
}

# Expected fonts for this task
EXPECTED_FONTS = {
    'standard': 'Times New Roman',
    'serif': 'Georgia',
    'sansserif': 'Arial',
    'fixed': 'Courier New'
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for font_family_config@1.
    
    Verifies that Chrome's font families have been customized according to task requirements.
    
    Scoring:
    - 100%: All 4 font families correctly configured
    - 75%: 3/4 font families correctly configured  
    - 50%: 2/4 font families correctly configured
    - 25%: 1/4 font families correctly configured
    - 0%: No fonts configured or file not accessible
    
    Pass threshold: 75% (at least 3 out of 4 fonts correctly set)
    
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
        # Extract font families from Chrome Preferences
        fonts_config, error_msg = extract_font_families(copy_from_env)
        
        if fonts_config is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract font configuration: {error_msg}"
            }
        
        # Validate font family configuration
        validation_result = validate_font_families(fonts_config, EXPECTED_FONTS)
        
        # Clean up temporary files
        cleanup_verification_temp()
        
        return validation_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_font_families(copy_from_env) -> Tuple[Optional[Dict[str, str]], str]:
    """
    Extract font family configurations from Chrome Preferences file.
    
    Handles multiple Chrome Preferences formats:
    - Nested structure: webkit.webprefs.fonts.standard.Zyyy
    - Nested with language codes: webkit.webprefs.fonts.standard.Latn
    - Flat structure: webkit.webprefs.standard_font_family
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (fonts_dict: Dict[str, str] or None, error_message: str)
        fonts_dict maps category names ('standard', 'serif', etc.) to font names
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
                
                if prefs:
                    fonts = extract_fonts_from_prefs(prefs)
                    if fonts:
                        return fonts, ""
                    else:
                        logger.warning("Utility extraction found no fonts, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_locations = [
            "/tmp/chrome_preferences_fonts.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs = None
        source_location = None
        
        for container_path in prefs_locations:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs = json.load(f)
                    source_location = container_path
                    logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                    break
                    
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs:
            return None, "Could not copy Preferences file from any location"
        
        # Extract fonts from preferences structure
        fonts = extract_fonts_from_prefs(prefs)
        
        if not fonts:
            return None, "No font configuration found in Preferences file"
        
        return fonts, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting fonts: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def extract_fonts_from_prefs(prefs: Dict[str, Any]) -> Optional[Dict[str, str]]:
    """
    Extract font families from parsed Preferences JSON.
    
    Handles multiple structure formats Chrome uses to store font preferences.
    
    Args:
        prefs: Parsed Preferences JSON as dictionary
        
    Returns:
        Dictionary mapping font category to font name, or None if not found
    """
    webkit = prefs.get('webkit', {})
    webprefs = webkit.get('webprefs', {})
    
    fonts = {}
    
    # Try nested structure: fonts.standard.Zyyy or fonts.standard.Latn
    fonts_section = webprefs.get('fonts', {})
    
    if fonts_section:
        for category in ['standard', 'serif', 'sansserif', 'fixed']:
            category_fonts = fonts_section.get(category, {})
            
            # Try common script codes
            for script_code in ['Zyyy', 'Latn', '*']:
                if script_code in category_fonts:
                    font_name = category_fonts[script_code]
                    if font_name:
                        fonts[category] = font_name
                        logger.info(f"Found {category} font (nested): {font_name}")
                        break
    
    # Try flat structure: standard_font_family, serif_font_family, etc.
    if not fonts or len(fonts) < 4:
        flat_mappings = {
            'standard': 'standard_font_family',
            'serif': 'serif_font_family',
            'sansserif': 'sansserif_font_family',
            'fixed': 'fixed_font_family'
        }
        
        for category, pref_key in flat_mappings.items():
            if category not in fonts:  # Don't override if already found
                font_name = webprefs.get(pref_key)
                if font_name:
                    fonts[category] = font_name
                    logger.info(f"Found {category} font (flat): {font_name}")
    
    # Also try alternative naming
    if 'sansserif' not in fonts:
        sans_serif = webprefs.get('sans_serif_font_family')
        if sans_serif:
            fonts['sansserif'] = sans_serif
    
    if 'fixed' not in fonts:
        monospace = webprefs.get('monospace_font_family') or webprefs.get('fixed_font_family')
        if monospace:
            fonts['fixed'] = monospace
    
    return fonts if fonts else None


def normalize_font_name(font_name: str) -> str:
    """
    Normalize font name for comparison.
    
    Handles variations in:
    - Case (Arial vs arial)
    - Quotes ("Arial" vs Arial)
    - Spaces (Courier New vs CourierNew)
    - Hyphens (Courier-New vs Courier New)
    
    Args:
        font_name: Raw font name string
        
    Returns:
        Normalized font name in lowercase without special characters
    """
    if not font_name:
        return ""
    
    # Remove quotes
    normalized = font_name.strip().strip('"').strip("'")
    
    # Convert to lowercase
    normalized = normalized.lower()
    
    # Remove spaces and hyphens for comparison
    normalized = normalized.replace(' ', '').replace('-', '')
    
    return normalized


def fonts_match(actual: str, expected: str) -> bool:
    """
    Check if two font names match after normalization.
    
    Args:
        actual: Font name from Preferences
        expected: Expected font name from task
        
    Returns:
        True if fonts match (case-insensitive, space-insensitive)
    """
    return normalize_font_name(actual) == normalize_font_name(expected)


def validate_font_families(fonts_config: Dict[str, str], expected_fonts: Dict[str, str]) -> Dict[str, Any]:
    """
    Validate that font families were correctly configured.
    
    Checks each font category against expected value and provides detailed feedback.
    
    Args:
        fonts_config: Actual font configuration from Preferences
        expected_fonts: Expected font configuration from task
        
    Returns:
        Verification result with passed, score, feedback, and details
    """
    validation_results = {}
    criteria_met = 0
    total_criteria = 4
    
    feedback_parts = []
    feedback_parts.append("Font Family Configuration Verification:")
    feedback_parts.append("=" * 50)
    
    # Check each font category
    for category, expected_font in expected_fonts.items():
        actual_font = fonts_config.get(category, "")
        
        if not actual_font:
            validation_results[category] = False
            status = "✗ NOT SET"
            feedback_parts.append(f"{category.capitalize()}: {status}")
            logger.info(f"{category}: not set in preferences")
        elif fonts_match(actual_font, expected_font):
            validation_results[category] = True
            criteria_met += 1
            status = f"✓ CORRECT: {actual_font}"
            feedback_parts.append(f"{category.capitalize()}: {status}")
            logger.info(f"{category}: correct - {actual_font}")
        else:
            validation_results[category] = False
            status = f"✗ WRONG: {actual_font} (expected: {expected_font})"
            feedback_parts.append(f"{category.capitalize()}: {status}")
            logger.info(f"{category}: wrong - got '{actual_font}', expected '{expected_font}'")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3 out of 4 fonts correct
    
    # Add summary
    feedback_parts.append("=" * 50)
    feedback_parts.append(f"Fonts configured correctly: {criteria_met}/{total_criteria}")
    feedback_parts.append(f"Score: {score}%")
    
    if passed:
        if score == 100:
            feedback_parts.append("✅ Perfect! All font families correctly configured.")
        else:
            feedback_parts.append("✅ Task passed with minor issues.")
    else:
        feedback_parts.append("❌ Task failed: Not enough fonts correctly configured.")
        feedback_parts.append("Required: At least 3 out of 4 fonts must be correctly set.")
    
    # Add detailed configuration summary
    feedback_parts.append("")
    feedback_parts.append("Expected configuration:")
    for category, font in expected_fonts.items():
        actual = fonts_config.get(category, "NOT SET")
        match_symbol = "✓" if validation_results.get(category, False) else "✗"
        feedback_parts.append(f"  {match_symbol} {category.capitalize()}: {font} (actual: {actual})")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "validation_results": validation_results,
            "actual_fonts": fonts_config,
            "expected_fonts": expected_fonts
        }
    }
