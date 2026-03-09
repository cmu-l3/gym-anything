#!/usr/bin/env python3
"""
Verifier for Zoom Video Region task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_zoom_video_region(traj, env_info, task_info):
    """
    Verify zoom video region task completion.

    Checks:
    1. VLC config file accessible and parseable
    2. Interactive zoom enabled (interactive-zoom=1)
    3. Zoom value set to approximately 2.0 (200%)

    VLC zoom settings:
    - interactive-zoom: 0 or 1 (disabled/enabled)
    - zoom: float value (1.0 = normal, 2.0 = 200%, etc.)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy zoom result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_zoom_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying zoom result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying zoom result: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Zoom config accessible")

        # Get zoom settings from result
        interactive_zoom = result.get('interactive_zoom', '0')
        zoom_value = result.get('zoom_value', '1.0')
        settings_found = result.get('settings_found', False)

        # Parse zoom value as float
        try:
            zoom_float = float(zoom_value)
        except (ValueError, TypeError):
            logger.error(f"Invalid zoom value format: {zoom_value}")
            os.unlink(temp_result.name)
            return {"passed": False, "score": 33, 
                    "feedback": f"Invalid zoom value format: {zoom_value}"}

        # Criterion 2: Check interactive zoom is enabled
        if interactive_zoom == '1':
            criteria_met += 1
            feedback_parts.append("✅ Interactive zoom enabled")
        else:
            feedback_parts.append(f"❌ Interactive zoom not enabled (value: {interactive_zoom}, expected: 1)")

        # Criterion 3: Check zoom value is approximately 2.0 (200%)
        target_zoom = 2.0
        tolerance = 0.15  # Allow 1.85 to 2.15
        
        if abs(zoom_float - target_zoom) <= tolerance:
            criteria_met += 1
            feedback_parts.append(f"✅ Zoom correctly set to {zoom_float}x (target: 2.0x)")
        else:
            # Partial credit if zoom was changed from default but not to correct value
            if abs(zoom_float - 1.0) > 0.05:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Zoom changed to {zoom_float}x but not at target 2.0x (±{tolerance})")
            else:
                feedback_parts.append(f"❌ Zoom not set correctly (value: {zoom_float}x, expected: 2.0x)")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error parsing zoom result JSON: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading zoom result: {str(e)}"}

    # Check completion marker (optional, doesn't affect score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_zoom_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        logger.info(f"Completion marker found: {marker_content}")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found (non-critical)")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    # Add helpful hints if failed
    if not passed:
        if interactive_zoom != '1':
            feedback += " | Hint: Enable 'Interactive Zoom' in Tools → Effects → Video Effects → Geometry"
        if abs(zoom_float - 2.0) > 0.15:
            feedback += f" | Hint: Adjust zoom slider to 2.0 (currently: {zoom_float})"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }