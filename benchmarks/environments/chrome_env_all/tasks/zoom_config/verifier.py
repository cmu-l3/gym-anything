#!/usr/bin/env python3
"""
Verifier for Chrome Zoom Configuration Task: zoom_config@1

This verifier checks that the agent successfully modified Chrome's default page zoom
setting from 100% to a larger value (ideally 125%-150%) for improved readability.

Verification Strategy:
1. Copy Chrome Preferences file from container
2. Parse JSON and extract zoom level setting
3. Verify zoom was changed from default (0 = 100%)
4. Validate zoom is in reasonable range for readability
5. Score based on appropriateness of zoom level
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Chrome zoom level mapping (internal value -> percentage)
ZOOM_MAPPING = {
    -5: 25, -4: 33, -3: 50, -2: 67, -1: 75,
    0: 100,  # Default
    1: 110, 2: 125, 3: 150, 4: 175, 5: 200,
    6: 250, 7: 300, 8: 400, 9: 500
}

# Ideal zoom range for readability (110%-150%)
IDEAL_ZOOM_MIN = 1  # 110%
IDEAL_ZOOM_MAX = 3  # 150%

# Acceptable zoom range (110%-200%)
ACCEPTABLE_ZOOM_MIN = 1  # 110%
ACCEPTABLE_ZOOM_MAX = 5  # 200%


def get_zoom_percentage(internal_value: int) -> int:
    """Convert Chrome internal zoom value to percentage"""
    return ZOOM_MAPPING.get(internal_value, -1)


def parse_chrome_preferences(prefs_path: str) -> Dict[str, Any]:
    """Parse Chrome Preferences JSON file"""
    try:
        with open(prefs_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing preferences: {e}")
        return {}


def extract_zoom_level(prefs: Dict[str, Any]) -> Tuple[bool, int, str]:
    """
    Extract default zoom level from Chrome Preferences
    
    Returns:
        Tuple of (found, zoom_level, path_used)
    """
    # Check multiple possible locations in different Chrome versions
    zoom_paths = [
        ['partition', 'default_zoom_level'],
        ['profile', 'default_zoom_level'],
        ['webkit', 'webprefs', 'default_zoom_level'],
        ['default_zoom_level']  # Root level (some versions)
    ]
    
    for path in zoom_paths:
        value = prefs
        path_str = '.'.join(path)
        
        try:
            for key in path:
                if not isinstance(value, dict):
                    break
                value = value.get(key)
                if value is None:
                    break
            
            # Check if we found a valid numeric zoom level
            if value is not None and isinstance(value, (int, float)):
                zoom_level = int(value)
                logger.info(f"Found zoom level at '{path_str}': {zoom_level}")
                return True, zoom_level, path_str
        except Exception as e:
            logger.debug(f"Error checking path '{path_str}': {e}")
            continue
    
    logger.warning("Zoom level setting not found in any expected location")
    return False, 0, ""


def validate_zoom_change(zoom_level: int) -> Tuple[bool, int, str]:
    """
    Validate that zoom level represents an appropriate change
    
    Returns:
        Tuple of (passed, score, feedback)
    """
    zoom_percent = get_zoom_percentage(zoom_level)
    
    # Check if zoom level is unchanged from default
    if zoom_level == 0:
        return False, 0, "Zoom level unchanged from default 100%"
    
    # Check if zoom was decreased (wrong direction)
    if zoom_level < 0:
        return False, 25, f"Zoom decreased to {zoom_percent}% instead of increased (wrong direction)"
    
    # Check if zoom is too high (above 200%)
    if zoom_level > ACCEPTABLE_ZOOM_MAX:
        return False, 50, f"Zoom level too high: {zoom_percent}% (above reasonable maximum of 200%)"
    
    # Ideal range: 110%-150% (values 1-3)
    if IDEAL_ZOOM_MIN <= zoom_level <= IDEAL_ZOOM_MAX:
        return True, 100, f"✓ Optimal zoom level for readability: {zoom_percent}%"
    
    # Acceptable but not ideal: 110%-200% (values 1-5)
    if ACCEPTABLE_ZOOM_MIN <= zoom_level <= ACCEPTABLE_ZOOM_MAX:
        return True, 75, f"Acceptable zoom level: {zoom_percent}% (slightly higher than ideal)"
    
    # Should not reach here, but handle edge cases
    return False, 50, f"Unexpected zoom level: {zoom_percent}%"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for zoom_config@1 task
    
    Args:
        traj: Trajectory information (not used in this verification)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (not used in this verification)
    
    Returns:
        Dict with keys: passed (bool), score (int 0-100), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Error: copy_from_env function not available"
        }
    
    temp_file = None
    try:
        # Step 1: Copy Chrome Preferences file from container
        logger.info("Copying Chrome Preferences file from container...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        try:
            copy_from_env("/tmp/chrome_preferences.json", temp_file.name)
        except Exception as copy_error:
            logger.error(f"Failed to copy preferences file: {copy_error}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to access Chrome Preferences file: {str(copy_error)}"
            }
        
        # Verify file was copied and has content
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Chrome Preferences file is missing or empty"
            }
        
        logger.info(f"Preferences file copied successfully ({os.path.getsize(temp_file.name)} bytes)")
        
        # Step 2: Parse Chrome Preferences JSON
        prefs = parse_chrome_preferences(temp_file.name)
        if not prefs:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse Chrome Preferences file (invalid JSON)"
            }
        
        logger.info("Preferences file parsed successfully")
        
        # Step 3: Extract zoom level setting
        found, zoom_level, path_used = extract_zoom_level(prefs)
        
        if not found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Zoom level setting not found in Chrome Preferences (setting may not have been modified)"
            }
        
        logger.info(f"Zoom level extracted: {zoom_level} (from {path_used})")
        
        # Step 4: Validate zoom change
        passed, score, feedback = validate_zoom_change(zoom_level)
        
        # Add detailed information to feedback
        zoom_percent = get_zoom_percentage(zoom_level)
        detailed_feedback = f"{feedback}\n"
        detailed_feedback += f"Details: Internal value={zoom_level}, Percentage={zoom_percent}%, "
        detailed_feedback += f"Source={path_used}"
        
        logger.info(f"Verification result: passed={passed}, score={score}")
        logger.info(f"Feedback: {detailed_feedback}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": detailed_feedback
        }
    
    except Exception as e:
        logger.error(f"Unexpected verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temporary file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
                logger.debug("Temporary file cleaned up")
            except Exception as cleanup_error:
                logger.warning(f"Failed to cleanup temp file: {cleanup_error}")
