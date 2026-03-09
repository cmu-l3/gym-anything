#!/usr/bin/env python3
"""Verifier for Zoom Image task"""

import sys
import os
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))


def verify_zoom_image(traj, env_info, task_info):
    """Verify that zoom was applied to the image."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 2
    feedback_parts = []

    metadata = task_info.get('metadata', {})
    target_zoom = metadata.get('target_zoom', 2.0)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criterion 1: Image was loaded
    if result.get('found', False):
        criteria_met += 1
        feedback_parts.append("Image loaded")
    else:
        feedback_parts.append("Image not detected")

    # Criterion 2: Zoom was changed
    zoom_changed = result.get('zoom_changed', False)
    current_zoom = float(result.get('current_zoom', 1.0))

    if zoom_changed:
        criteria_met += 1
        if current_zoom >= target_zoom:
            feedback_parts.append(f"Zoomed to {current_zoom}x (target: {target_zoom}x)")
        else:
            feedback_parts.append(f"Zoomed to {current_zoom}x (target was {target_zoom}x)")
    else:
        # Check screenshot diff as fallback
        screenshot_diff = float(result.get('screenshot_diff', 0))
        if screenshot_diff > 100:
            criteria_met += 1
            feedback_parts.append(f"Visual change detected (likely zoomed)")
        else:
            feedback_parts.append("No zoom detected")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
