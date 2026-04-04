#!/usr/bin/env python3
"""
Verifier for Capture 3D View task in 3D Slicer.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_capture_3d_view(traj, env_info, task_info):
    """
    Verify that 3D volume rendering was enabled and screenshot captured.

    Checks:
    1. Screenshot was captured
    2. Screenshot shows 3D rendered content (size/variety)
    3. User saved a screenshot via Slicer
    4. Data was loaded
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    min_screenshot_size_kb = metadata.get('min_screenshot_size_kb', 100)

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/slicer_3d_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: Final screenshot exists and has content
    if result.get('screenshot_exists', False):
        screenshot_size = result.get('screenshot_size_kb', 0)
        if screenshot_size > min_screenshot_size_kb / 2:
            criteria_met += 1
            feedback_parts.append(f"Screenshot captured ({screenshot_size}KB)")
        else:
            criteria_met += 0.5
            feedback_parts.append(f"Screenshot small ({screenshot_size}KB)")
    else:
        feedback_parts.append("No screenshot captured")

    # Criterion 2: Screenshot has 3D content
    has_3d = result.get('screenshot_has_3d_content', False)
    screenshot_size = result.get('screenshot_size_kb', 0)

    if has_3d:
        criteria_met += 1
        feedback_parts.append("3D content detected")
    elif screenshot_size > min_screenshot_size_kb:
        criteria_met += 0.5
        feedback_parts.append("Possible 3D content")
    else:
        feedback_parts.append("No 3D content detected")

    # Criterion 3: User saved screenshot via Slicer
    user_screenshot = result.get('user_screenshot_exists', False)
    user_screenshot_size = result.get('user_screenshot_size_kb', 0)
    new_screenshots = result.get('new_screenshots_count', 0)

    if user_screenshot and user_screenshot_size > 50:
        criteria_met += 1
        feedback_parts.append(f"User saved screenshot ({user_screenshot_size}KB)")
    elif new_screenshots > 0:
        criteria_met += 0.5
        feedback_parts.append(f"{new_screenshots} new screenshot(s)")
    else:
        feedback_parts.append("No user screenshot saved")

    # Criterion 4: Data was loaded
    data_loaded = result.get('data_loaded', False)
    volume_rendering = result.get('volume_rendering_active', False)

    if data_loaded and volume_rendering:
        criteria_met += 1
        feedback_parts.append("Volume rendering active")
    elif data_loaded:
        criteria_met += 0.5
        feedback_parts.append("Data loaded")
    else:
        feedback_parts.append("Data not loaded")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 60  # Pass if at least 60% criteria met

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": result
    }
