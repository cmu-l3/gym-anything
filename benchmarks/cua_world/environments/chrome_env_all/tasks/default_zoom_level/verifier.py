#!/usr/bin/env python3
"""
Verifier for Chrome Default Zoom Level Configuration Task (default_zoom_level@1)
Task: Configure Chrome's default page zoom level from 100% to a different percentage

Verification Strategy:
- Copy Chrome Preferences file from container
- Parse JSON and extract zoom level setting from multiple possible locations
- Convert Chrome's internal zoom factor to percentage
- Validate that zoom level differs from default 100%
- Ensure new value is within Chrome's supported range (25%-500%)
- Check if value matches Chrome's standard zoom levels
"""

import logging
import sys
import os
import json
import math
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../utils'))
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


# Chrome's standard zoom levels
STANDARD_ZOOM_LEVELS = [25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500]


def zoom_factor_to_percent(factor: float) -> float:
    """
    Convert Chrome's internal zoom factor to percentage.
    
    Chrome uses: factor = log(percent/100) / log(1.2)
    Inverse: percent = 100 * (1.2 ^ factor)
    
    Args:
        factor: Chrome's internal zoom factor
        
    Returns:
        Zoom percentage (e.g., 125.0 for 125%)
    """
    try:
        zoom_percent = 100.0 * math.pow(1.2, factor)
        return round(zoom_percent)
    except Exception as e:
        logger.error(f"Error converting zoom factor {factor}: {e}")
        return 100.0


def zoom_percent_to_factor(percent: float) -> float:
    """
    Convert zoom percentage to Chrome's internal factor.
    
    Args:
        percent: Zoom percentage (e.g., 125 for 125%)
        
    Returns:
        Chrome's internal zoom factor
    """
    try:
        if percent <= 0:
            return 0.0
        return math.log(percent / 100.0) / math.log(1.2)
    except Exception as e:
        logger.error(f"Error converting zoom percent {percent}: {e}")
        return 0.0


def is_standard_zoom(percent: float, tolerance: float = 2.0) -> bool:
    """
    Check if zoom percentage is close to a standard Chrome level.
    
    Args:
        percent: Zoom percentage to check
        tolerance: Allowed deviation from standard levels
        
    Returns:
        True if close to a standard level
    """
    return any(abs(percent - std) <= tolerance for std in STANDARD_ZOOM_LEVELS)


def find_closest_standard(percent: float) -> int:
    """Find the closest standard zoom level to given percentage."""
    return min(STANDARD_ZOOM_LEVELS, key=lambda x: abs(x - percent))


def extract_zoom_factor_from_prefs(prefs_data: Dict[str, Any]) -> Optional[float]:
    """
    Extract zoom factor from Chrome Preferences data.
    
    Checks multiple possible locations:
    - partition.default_zoom_level.x
    - partition.default_zoom_level (direct value)
    - profile.default_zoom_level
    - webkit.webprefs.default_zoom_level
    
    Args:
        prefs_data: Parsed Chrome Preferences JSON
        
    Returns:
        Zoom factor as float, or None if not found
    """
    # Location 1: partition.default_zoom_level (modern Chrome)
    if 'partition' in prefs_data:
        partition = prefs_data['partition']
        if 'default_zoom_level' in partition:
            zoom_data = partition['default_zoom_level']
            
            # Could be {"x": 1.0} or just 1.0
            if isinstance(zoom_data, dict) and 'x' in zoom_data:
                logger.info(f"Found zoom factor in partition.default_zoom_level.x: {zoom_data['x']}")
                return float(zoom_data['x'])
            elif isinstance(zoom_data, (int, float)):
                logger.info(f"Found zoom factor in partition.default_zoom_level: {zoom_data}")
                return float(zoom_data)
    
    # Location 2: profile.default_zoom_level
    if 'profile' in prefs_data:
        profile = prefs_data['profile']
        if 'default_zoom_level' in profile:
            zoom_data = profile['default_zoom_level']
            if isinstance(zoom_data, (int, float)):
                logger.info(f"Found zoom factor in profile.default_zoom_level: {zoom_data}")
                return float(zoom_data)
    
    # Location 3: webkit.webprefs.default_zoom_level (legacy)
    if 'webkit' in prefs_data:
        webkit = prefs_data['webkit']
        if 'webprefs' in webkit:
            webprefs = webkit['webprefs']
            if 'default_zoom_level' in webprefs:
                zoom_data = webprefs['default_zoom_level']
                if isinstance(zoom_data, (int, float)):
                    logger.info(f"Found zoom factor in webkit.webprefs.default_zoom_level: {zoom_data}")
                    return float(zoom_data)
    
    logger.warning("Zoom factor not found in any known location")
    return None


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for default_zoom_level@1.
    
    Verifies that Chrome's default zoom level has been changed from 100%.
    
    Verification Criteria (5 total, need 4+ for passing):
    1. Preferences file accessible
    2. Zoom setting found in preferences
    3. Zoom level changed from default 100%
    4. Zoom level within valid range (25%-500%)
    5. Zoom level matches a standard Chrome zoom option
    
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
        # Extract zoom level from preferences
        zoom_percent, zoom_factor, error_msg = get_zoom_level_from_container(copy_from_env)
        
        if zoom_percent is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to extract zoom level: {error_msg}"
            }
        
        # Perform multi-criteria validation
        validation_result = validate_zoom_configuration(zoom_percent, zoom_factor)
        
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


def get_zoom_level_from_container(copy_from_env) -> Tuple[Optional[float], Optional[float], str]:
    """
    Retrieve and parse zoom level from Chrome Preferences in container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (zoom_percent, zoom_factor, error_message)
    """
    temp_file = None
    try:
        # Try using utilities if available
        if UTILS_AVAILABLE:
            logger.info("Attempting to use chrome_verification_utils...")
            try:
                success, files, error = setup_chrome_verification(
                    copy_from_env,
                    ["Preferences"],
                    user="ga",
                    profile="Default"
                )
                
                if success:
                    prefs_data = parse_preferences(files["Preferences"])
                    cleanup_verification_temp()
                    
                    zoom_factor = extract_zoom_factor_from_prefs(prefs_data)
                    if zoom_factor is not None:
                        zoom_percent = zoom_factor_to_percent(zoom_factor)
                        return zoom_percent, zoom_factor, ""
                    else:
                        return None, None, "Zoom setting not found in Preferences"
                else:
                    logger.warning(f"Utility-based extraction failed: {error}, trying fallback")
            except Exception as e:
                logger.warning(f"Utility method failed: {e}, using fallback")
        
        # Fallback: Manual extraction
        logger.info("Using fallback method to extract zoom level...")
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        
        # Try multiple possible locations
        prefs_paths = [
            "/tmp/chrome_zoom_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences"
        ]
        
        prefs_data = None
        for container_path in prefs_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_file.name)
                
                # Check if file was copied successfully
                if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                    with open(temp_file.name, 'r', encoding='utf-8') as f:
                        prefs_data = json.load(f)
                    logger.info(f"Successfully copied and parsed Preferences from: {container_path}")
                    break
            except Exception as e:
                logger.debug(f"Failed to copy from {container_path}: {e}")
                continue
        
        if prefs_data is None:
            return None, None, "Could not access Preferences file from any known location"
        
        # Extract zoom factor
        zoom_factor = extract_zoom_factor_from_prefs(prefs_data)
        
        if zoom_factor is None:
            return None, None, "Zoom level setting not found in Preferences"
        
        # Convert to percentage
        zoom_percent = zoom_factor_to_percent(zoom_factor)
        logger.info(f"Extracted zoom: factor={zoom_factor}, percent={zoom_percent}%")
        
        return zoom_percent, zoom_factor, ""
        
    except json.JSONDecodeError as e:
        return None, None, f"Failed to parse Preferences JSON: {e}"
    except Exception as e:
        return None, None, f"Error extracting zoom level: {e}"
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass


def validate_zoom_configuration(zoom_percent: float, zoom_factor: float) -> Dict[str, Any]:
    """
    Validate that zoom level was appropriately configured.
    
    Checks:
    1. Zoom differs from default 100%
    2. Zoom is within valid range (25%-500%)
    3. Zoom matches a standard Chrome level (or is close)
    4. Zoom is reasonable for readability improvements
    
    Args:
        zoom_percent: Zoom level as percentage
        zoom_factor: Chrome's internal zoom factor
        
    Returns:
        Dict with passed, score, feedback, and details
    """
    DEFAULT_ZOOM = 100.0
    MIN_VALID = 25
    MAX_VALID = 500
    RECOMMENDED_MIN = 110
    RECOMMENDED_MAX = 200
    
    criteria_results = []
    feedback_parts = []
    
    # Criterion 1: Changed from default
    is_changed = abs(zoom_percent - DEFAULT_ZOOM) > 1.0
    criteria_results.append(is_changed)
    
    if is_changed:
        feedback_parts.append(f"✓ Zoom level changed to {zoom_percent}% (was {DEFAULT_ZOOM}%)")
    else:
        feedback_parts.append(f"✗ Zoom level unchanged from default ({DEFAULT_ZOOM}%)")
    
    # Criterion 2: Within valid range
    in_valid_range = MIN_VALID <= zoom_percent <= MAX_VALID
    criteria_results.append(in_valid_range)
    
    if in_valid_range:
        feedback_parts.append(f"✓ Zoom level within valid range ({MIN_VALID}%-{MAX_VALID}%)")
    else:
        feedback_parts.append(f"✗ Zoom level {zoom_percent}% outside valid range ({MIN_VALID}%-{MAX_VALID}%)")
    
    # Criterion 3: Matches standard zoom level
    is_standard = is_standard_zoom(zoom_percent)
    criteria_results.append(is_standard)
    
    if is_standard:
        feedback_parts.append(f"✓ Zoom level matches a standard Chrome zoom option")
    else:
        closest = find_closest_standard(zoom_percent)
        feedback_parts.append(f"⚠ Zoom level {zoom_percent}% is non-standard (closest: {closest}%)")
        # Still give partial credit for non-standard but reasonable values
        if abs(zoom_percent - closest) <= 5:
            criteria_results[-1] = 0.7  # Partial credit
    
    # Criterion 4: Reasonable for readability (in recommended range)
    in_recommended_range = RECOMMENDED_MIN <= zoom_percent <= RECOMMENDED_MAX
    criteria_results.append(in_recommended_range)
    
    if in_recommended_range:
        feedback_parts.append(f"✓ Zoom level in recommended range for readability ({RECOMMENDED_MIN}%-{RECOMMENDED_MAX}%)")
    else:
        if zoom_percent < RECOMMENDED_MIN:
            feedback_parts.append(f"⚠ Zoom level {zoom_percent}% is below recommended minimum ({RECOMMENDED_MIN}%)")
        else:
            feedback_parts.append(f"⚠ Zoom level {zoom_percent}% is above recommended maximum ({RECOMMENDED_MAX}%)")
        # Still give partial credit if changed and valid
        if is_changed and in_valid_range:
            criteria_results[-1] = 0.5
    
    # Calculate score
    # Convert any partial credits (floats) to their value
    total_criteria = len(criteria_results)
    criteria_met = sum(1.0 if c is True else (c if isinstance(c, float) else 0.0) for c in criteria_results)
    score = int((criteria_met / total_criteria) * 100)
    
    # Determine pass/fail (need >= 75%, which is 3/4 criteria)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nZoom configuration: {zoom_percent}% (factor: {zoom_factor:.3f})"
    
    if passed:
        if score >= 95:
            feedback += f"\n\n✅ Excellent! Zoom level optimally configured for improved readability."
        else:
            feedback += f"\n\n✅ Task completed successfully. Zoom level configured."
    else:
        feedback += f"\n\n❌ Task incomplete or zoom level not properly configured."
    
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, zoom={zoom_percent}%")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "zoom_percent": zoom_percent,
            "zoom_factor": zoom_factor,
            "default_zoom": DEFAULT_ZOOM,
            "difference": zoom_percent - DEFAULT_ZOOM,
            "is_standard": is_standard,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }
