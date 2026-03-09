#!/usr/bin/env python3
"""
Verifier for Chrome Font Size Configuration Task (font_size_config@1)
Task: Increase Chrome's default font size for better readability

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract webkit.webprefs.default_font_size
- Validate that font size is increased from default (16px)
- Ensure new value is within reasonable bounds (17-24px)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import (
        setup_chrome_verification,
        cleanup_verification_temp,
        parse_preferences,
        get_font_size
    )
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False


def verify_task(traj, env_info, task_info):
    """
    Main verification function for font_size_config@1.
    
    Verifies that Chrome's default font size has been increased from the default value.
    
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
        # Get font size from Chrome Preferences
        font_size, error_msg = extract_font_size_from_prefs(copy_from_env)
        
        if font_size is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract font size: {error_msg}"
            }
        
        # Validate font size
        is_valid, score, feedback = validate_font_size_change(font_size)
        
        return {
            "passed": is_valid,
            "score": score,
            "feedback": feedback,
            "details": {
                "font_size": font_size,
                "default": 16,
                "increase": font_size - 16
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def extract_font_size_from_prefs(copy_from_env):
    """
    Extract font size setting from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (font_size: int or None, error_message: str)
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
                font_sizes = get_font_size(prefs_path)
                cleanup_verification_temp()
                
                default_font_size = font_sizes.get('default_font_size', 16)
                return default_font_size, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try primary location
        try:
            copy_from_env("/tmp/chrome_preferences.json", temp_file.name)
        except Exception as e:
            logger.warning(f"Failed to copy from /tmp/chrome_preferences.json: {e}")
            # Try copying directly from profile
            try:
                copy_from_env("/home/ga/.config/google-chrome-cdp/Default/Preferences", temp_file.name)
            except Exception as e2:
                # Try alternative profile location
                try:
                    copy_from_env("/home/ga/.config/google-chrome/Default/Preferences", temp_file.name)
                except Exception as e3:
                    return None, f"Could not copy Preferences file from any location: {e3}"
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
        
        # Navigate nested structure to extract font size
        webkit = prefs.get('webkit', {})
        webprefs = webkit.get('webprefs', {})
        default_font_size = webprefs.get('default_font_size', 16)
        
        logger.info(f"Extracted default_font_size: {default_font_size}")
        
        return default_font_size, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting font size: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def validate_font_size_change(font_size):
    """
    Validate that font size was appropriately increased.
    
    Args:
        font_size: Integer font size in pixels
        
    Returns:
        Tuple of (is_valid: bool, score: int, feedback: str)
    """
    DEFAULT_FONT_SIZE = 16
    MIN_ACCEPTABLE = 17
    MAX_ACCEPTABLE = 24
    OPTIMAL_MIN = 18
    OPTIMAL_MAX = 22
    
    # Check if unchanged from default
    if font_size == DEFAULT_FONT_SIZE:
        return False, 0, f"Font size unchanged from default ({DEFAULT_FONT_SIZE}px). Please increase it in Chrome Settings > Appearance."
    
    # Check if decreased (wrong direction)
    if font_size < DEFAULT_FONT_SIZE:
        return False, 0, f"Font size was decreased to {font_size}px instead of increased. Default is {DEFAULT_FONT_SIZE}px."
    
    # Check if too small an increase
    if font_size < MIN_ACCEPTABLE:
        return False, 25, f"Font size increase to {font_size}px is too small to be meaningful (only +{font_size - DEFAULT_FONT_SIZE}px)."
    
    # Check if unreasonably large
    if font_size > MAX_ACCEPTABLE:
        return False, 50, f"Font size of {font_size}px is unreasonably large (maximum acceptable is {MAX_ACCEPTABLE}px)."
    
    # Marginal increase (just barely above default)
    if font_size == MIN_ACCEPTABLE:
        return True, 75, f"Font size increased to {font_size}px (+{font_size - DEFAULT_FONT_SIZE}px). This is a minimal but acceptable increase."
    
    # Near maximum (might be too large for some users)
    if font_size in [23, 24]:
        return True, 85, f"Font size increased to {font_size}px (+{font_size - DEFAULT_FONT_SIZE}px). This is near the maximum recommended size."
    
    # Optimal range
    if OPTIMAL_MIN <= font_size <= OPTIMAL_MAX:
        return True, 100, f"Font size optimally increased to {font_size}px (+{font_size - DEFAULT_FONT_SIZE}px). Excellent choice for improved readability!"
    
    # Any other valid increase
    return True, 90, f"Font size increased to {font_size}px (+{font_size - DEFAULT_FONT_SIZE}px). Good configuration."
