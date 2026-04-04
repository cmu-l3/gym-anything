#!/usr/bin/env python3
"""
Verifier for Chrome Accessibility Font Configuration Task (accessibility_fonts@1)
Task: Configure Chrome font sizes for improved accessibility

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract webkit.webprefs font size settings
- Validate three font sizes: default (20px), minimum (12px), fixed-width (16px)
- Check logical consistency (minimum <= default)
- Ensure values are in reasonable range (6-72px)

Scoring:
- 100%: All 3 font sizes correct + logical consistency + valid range
- 75-99%: 2/3 font sizes correct
- 50-74%: 1/3 font sizes correct
- 0-49%: 0/3 correct or invalid configuration

Pass threshold: 75% (requires at least 2 out of 3 font sizes correct)
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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
try:
    from chrome_verification_utils import (
        copy_chrome_file,
        parse_preferences,
        get_font_size,
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


def extract_font_sizes_from_preferences(copy_from_env) -> Tuple[Optional[Dict[str, int]], str]:
    """
    Extract font size settings from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container to host
        
    Returns:
        Tuple of (font_sizes_dict, error_message)
        font_sizes_dict contains: 'default_font_size', 'minimum_font_size', 'default_fixed_font_size'
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use chrome_verification_utils...")
            try:
                success, prefs_path, error = copy_chrome_file(
                    "Preferences",
                    copy_from_env,
                    user="ga",
                    profile="Default"
                )
                
                if success:
                    font_sizes = get_font_size(prefs_path)
                    logger.info(f"Successfully extracted font sizes using utils: {font_sizes}")
                    return font_sizes, ""
                else:
                    logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
            except Exception as e:
                logger.warning(f"Exception using utils: {e}, trying fallback")
        
        # Fallback: Manual extraction
        logger.info("Using fallback manual extraction...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/chrome_preferences_fonts.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        source_path = None
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully and has content
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    source_path = container_path
                    logger.info(f"✓ Successfully copied and parsed from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if not prefs_data:
            return None, "Could not access Preferences file from any known location"
        
        # Navigate nested structure to extract font sizes
        webkit = prefs_data.get('webkit', {})
        webprefs = webkit.get('webprefs', {})
        
        if not webprefs:
            return None, "webkit.webprefs not found in Preferences structure"
        
        font_sizes = {
            'default_font_size': webprefs.get('default_font_size'),
            'minimum_font_size': webprefs.get('minimum_font_size'),
            'default_fixed_font_size': webprefs.get('default_fixed_font_size')
        }
        
        logger.info(f"Extracted font sizes: {font_sizes}")
        
        # Check if any values are missing
        if any(v is None for v in font_sizes.values()):
            missing = [k for k, v in font_sizes.items() if v is None]
            return None, f"Missing font size values in Preferences: {missing}"
        
        return font_sizes, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        logger.error(f"Error extracting font sizes: {e}", exc_info=True)
        return None, f"Error extracting font sizes: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def verify_font_configuration(font_sizes: Dict[str, int]) -> Dict[str, Any]:
    """
    Verify that font sizes are correctly configured.
    
    Target values:
    - default_font_size: 20
    - minimum_font_size: 12
    - default_fixed_font_size: 16
    
    Args:
        font_sizes: Dictionary with 'default_font_size', 'minimum_font_size', 'default_fixed_font_size'
        
    Returns:
        Dict with verification results including passed, score, feedback, and detailed checks
    """
    # Target values
    TARGET_DEFAULT = 20
    TARGET_MINIMUM = 12
    TARGET_FIXED = 16
    
    # Extract actual values
    default_size = font_sizes.get('default_font_size')
    minimum_size = font_sizes.get('minimum_font_size')
    fixed_size = font_sizes.get('default_fixed_font_size')
    
    # Individual criteria checks
    default_correct = (default_size == TARGET_DEFAULT)
    minimum_correct = (minimum_size == TARGET_MINIMUM)
    fixed_correct = (fixed_size == TARGET_FIXED)
    
    # Logical consistency check: minimum should not exceed default
    logical_consistency = True
    if default_size and minimum_size:
        logical_consistency = minimum_size <= default_size
    
    # Range validity check: all sizes should be in reasonable range (6-72px)
    range_valid = True
    for size in [default_size, minimum_size, fixed_size]:
        if size is not None:
            if not (6 <= size <= 72):
                range_valid = False
                break
    
    # Calculate score
    correct_count = sum([default_correct, minimum_correct, fixed_correct])
    
    # Scoring logic:
    # - All 3 correct + logical + range valid = 100%
    # - 2/3 correct = 75%
    # - 1/3 correct = 50%
    # - 0/3 correct = 0%
    # Penalties for logical inconsistency or invalid range
    
    if correct_count == 3 and logical_consistency and range_valid:
        score = 100
        passed = True
        feedback = "Perfect! All font sizes correctly configured for accessibility."
    elif correct_count == 3:
        score = 90
        passed = True
        feedback = "All font sizes correct, but "
        if not logical_consistency:
            feedback += "minimum font size exceeds default (illogical). "
        if not range_valid:
            feedback += "some values outside reasonable range. "
    elif correct_count == 2:
        score = 75
        passed = True
        feedback = f"Good! {correct_count}/3 font sizes correctly configured. "
        if not default_correct:
            feedback += f"Default font size is {default_size}px (expected {TARGET_DEFAULT}px). "
        if not minimum_correct:
            feedback += f"Minimum font size is {minimum_size}px (expected {TARGET_MINIMUM}px). "
        if not fixed_correct:
            feedback += f"Fixed-width font size is {fixed_size}px (expected {TARGET_FIXED}px). "
    elif correct_count == 1:
        score = 50
        passed = False
        feedback = f"Partial: Only {correct_count}/3 font sizes correct. "
        feedback += f"Current: default={default_size}px (need {TARGET_DEFAULT}px), "
        feedback += f"minimum={minimum_size}px (need {TARGET_MINIMUM}px), "
        feedback += f"fixed={fixed_size}px (need {TARGET_FIXED}px)"
    else:
        score = 0
        passed = False
        feedback = f"Failed: No font sizes correctly configured. "
        feedback += f"Current: default={default_size}px (need {TARGET_DEFAULT}px), "
        feedback += f"minimum={minimum_size}px (need {TARGET_MINIMUM}px), "
        feedback += f"fixed={fixed_size}px (need {TARGET_FIXED}px)"
    
    # Add warnings for logical or range issues
    if not logical_consistency:
        feedback += f"\n⚠ Warning: Minimum font size ({minimum_size}px) exceeds default ({default_size}px) - illogical configuration."
    
    if not range_valid:
        feedback += "\n⚠ Warning: Some font sizes outside reasonable range (6-72px)."
    
    # Detailed breakdown
    details = {
        "default_font_size": {
            "actual": default_size,
            "expected": TARGET_DEFAULT,
            "correct": default_correct
        },
        "minimum_font_size": {
            "actual": minimum_size,
            "expected": TARGET_MINIMUM,
            "correct": minimum_correct
        },
        "default_fixed_font_size": {
            "actual": fixed_size,
            "expected": TARGET_FIXED,
            "correct": fixed_correct
        },
        "logical_consistency": logical_consistency,
        "range_valid": range_valid,
        "correct_count": correct_count
    }
    
    logger.info(f"Verification results: {correct_count}/3 correct, score={score}%, passed={passed}")
    logger.info(f"  Default: {default_size} (target {TARGET_DEFAULT}) - {'✓' if default_correct else '✗'}")
    logger.info(f"  Minimum: {minimum_size} (target {TARGET_MINIMUM}) - {'✓' if minimum_correct else '✗'}")
    logger.info(f"  Fixed: {fixed_size} (target {TARGET_FIXED}) - {'✓' if fixed_correct else '✗'}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for accessibility_fonts@1 task.
    
    Verifies that Chrome font sizes are configured for accessibility:
    - Default font size: 20px
    - Minimum font size: 12px
    - Fixed-width font size: 16px
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str), and details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Extract font sizes from Preferences file
        logger.info("Extracting font sizes from Chrome Preferences...")
        font_sizes, error_msg = extract_font_sizes_from_preferences(copy_from_env)
        
        if font_sizes is None:
            cleanup_verification_temp()
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract font sizes: {error_msg}"
            }
        
        # Verify font configuration
        result = verify_font_configuration(font_sizes)
        
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
