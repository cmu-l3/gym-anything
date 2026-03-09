#!/usr/bin/env python3
"""
Verifier for Chrome Live Captions Configuration Task (live_captions_config@1)
Task: Enable Live Captions and customize caption styling for accessibility

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract accessibility.captions settings
- Verify live_caption_enabled is true
- Verify caption styling is customized (text_size, font, colors)
- Score based on 5 criteria (enabled + 4 styling customizations)
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


# Default caption settings for Chrome
DEFAULT_CAPTION_SETTINGS = {
    'live_caption_enabled': False,
    'text_size': '100%',
    'text_font': 'Proportional Sans-Serif',
    'text_color': '#FFFFFF',
    'background_color': '#000000',
}

# Alternative default values that Chrome might use
ALTERNATIVE_DEFAULTS = {
    'text_size': ['', '1', '1.0', 'medium', 'Medium'],
    'text_font': ['', 'sans-serif', 'default', 'Default'],
    'text_color': ['#FFF', '#fff', 'white', 'White', ''],
    'background_color': ['#000', '#000000', 'black', 'Black', ''],
}


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for live_captions_config@1.
    
    Verifies that Chrome Live Captions has been enabled and caption styling
    has been customized appropriately.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Extract caption settings from Chrome Preferences
        caption_settings, error_msg = extract_caption_settings(copy_from_env)
        
        if caption_settings is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract caption settings: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_caption_configuration(caption_settings)
        
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


def extract_caption_settings(copy_from_env) -> Tuple[Optional[Dict[str, Any]], str]:
    """
    Extract caption settings from Chrome Preferences file.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (caption_settings dict or None, error_message)
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
                
                # Extract caption settings
                accessibility = prefs.get('accessibility', {})
                captions = accessibility.get('captions', {})
                
                logger.info(f"Extracted caption settings: {captions}")
                return captions, ""
            else:
                logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
        
        # Fallback: Manual extraction
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        locations_tried = []
        for container_path in [
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    logger.info(f"✓ Successfully copied from: {container_path}")
                    break
                else:
                    locations_tried.append(container_path)
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                locations_tried.append(container_path)
                continue
        else:
            # If we exit the loop without break, none of the locations worked
            return None, f"Could not copy Preferences file from any location: {', '.join(locations_tried)}"
        
        # Parse JSON
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            prefs = json.load(f)
        
        # Navigate nested structure to extract caption settings
        accessibility = prefs.get('accessibility', {})
        captions = accessibility.get('captions', {})
        
        logger.info(f"Extracted caption settings: {captions}")
        
        return captions, ""
        
    except json.JSONDecodeError as e:
        return None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, f"Error extracting caption settings: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def is_default_value(key: str, value: Any) -> bool:
    """
    Check if a setting value is still at its default.
    
    Args:
        key: Setting key (e.g., 'text_size', 'text_color')
        value: Current value of the setting
        
    Returns:
        True if value appears to be default, False if customized
    """
    if value is None or value == '':
        return True
    
    # Check against primary default
    primary_default = DEFAULT_CAPTION_SETTINGS.get(key)
    if value == primary_default:
        return True
    
    # Check against alternative defaults
    alternatives = ALTERNATIVE_DEFAULTS.get(key, [])
    if value in alternatives:
        return True
    
    return False


def verify_caption_configuration(caption_settings: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that Live Captions is enabled and styling is customized.
    
    Checks 5 criteria:
    1. Live Captions enabled
    2. Text size customized
    3. Font family customized
    4. Text color customized
    5. Background color customized
    
    Args:
        caption_settings: Dict of caption configuration from Preferences
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Live Captions enabled
    live_caption_enabled = caption_settings.get('live_caption_enabled', False)
    if live_caption_enabled is True or live_caption_enabled == 'true':
        feedback_parts.append("✓ Live Captions enabled")
        criteria_met += 1
        logger.info("✓ Live Captions is enabled")
    else:
        feedback_parts.append("✗ Live Captions not enabled (required)")
        logger.info(f"✗ Live Captions not enabled (value: {live_caption_enabled})")
    
    # Criterion 2: Text size customized
    text_size = caption_settings.get('text_size', '100%')
    if not is_default_value('text_size', text_size):
        feedback_parts.append(f"✓ Text size customized: {text_size}")
        criteria_met += 1
        logger.info(f"✓ Text size customized to: {text_size}")
    else:
        feedback_parts.append(f"✗ Text size not customized (still at default: {text_size})")
        logger.info(f"✗ Text size appears to be default: {text_size}")
    
    # Criterion 3: Font family customized
    text_font = caption_settings.get('text_font', 'Proportional Sans-Serif')
    if not is_default_value('text_font', text_font):
        feedback_parts.append(f"✓ Font customized: {text_font}")
        criteria_met += 1
        logger.info(f"✓ Font customized to: {text_font}")
    else:
        feedback_parts.append(f"✗ Font not customized (still at default: {text_font})")
        logger.info(f"✗ Font appears to be default: {text_font}")
    
    # Criterion 4: Text color customized
    text_color = caption_settings.get('text_color', '#FFFFFF')
    if not is_default_value('text_color', text_color):
        feedback_parts.append(f"✓ Text color customized: {text_color}")
        criteria_met += 1
        logger.info(f"✓ Text color customized to: {text_color}")
    else:
        feedback_parts.append(f"✗ Text color not customized (still at default: {text_color})")
        logger.info(f"✗ Text color appears to be default: {text_color}")
    
    # Criterion 5: Background color customized
    bg_color = caption_settings.get('background_color', '#000000')
    if not is_default_value('background_color', bg_color):
        feedback_parts.append(f"✓ Background color customized: {bg_color}")
        criteria_met += 1
        logger.info(f"✓ Background color customized to: {bg_color}")
    else:
        feedback_parts.append(f"✗ Background color not customized (still at default: {bg_color})")
        logger.info(f"✗ Background color appears to be default: {bg_color}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = criteria_met >= 4  # Need 4/5 criteria (80%) to pass
    
    # Build comprehensive feedback
    feedback = "Live Captions Configuration Verification\n"
    feedback += "=" * 50 + "\n"
    feedback += f"Criteria met: {criteria_met}/{total_criteria}\n\n"
    feedback += "\n".join(feedback_parts)
    feedback += "\n" + "=" * 50 + "\n"
    
    if passed:
        feedback += f"✅ PASSED (Score: {score}%)\n"
        feedback += "Live Captions successfully configured with custom styling!"
    else:
        feedback += f"❌ FAILED (Score: {score}%)\n"
        if not live_caption_enabled:
            feedback += "Live Captions must be enabled first.\n"
        feedback += f"Need at least 4/{total_criteria} criteria met to pass.\n"
        feedback += "Ensure you customize caption appearance in Caption Preferences."
    
    logger.info(f"Final verification: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "live_caption_enabled": live_caption_enabled,
            "text_size": text_size,
            "text_font": text_font,
            "text_color": text_color,
            "background_color": bg_color
        }
    }
