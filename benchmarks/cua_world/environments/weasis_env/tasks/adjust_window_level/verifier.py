#!/usr/bin/env python3
"""
Verifier for Adjust Window Level task
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adjust_window_level(traj, env_info, task_info):
    """
    Verify that window/level settings were adjusted.

    Checks:
    1. Result file exists and is valid
    2. Window/level was changed (based on detection methods)
    3. Image display changed significantly (screenshot diff)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Get expected initial values from task metadata
    metadata = task_info.get('metadata', {})
    expected_initial_wc = metadata.get('initial_window_center', 40)
    expected_initial_ww = metadata.get('initial_window_width', 400)

    # Copy result file from container
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

    # Criterion 1: Result file is valid and image was loaded
    if result.get('found', False):
        criteria_met += 1
        feedback_parts.append("Image loaded")
    else:
        feedback_parts.append("Image not detected")

    # Criterion 2: Window/level change detected
    wl_changed = result.get('wl_changed', False)
    initial_wc = result.get('initial_window_center', expected_initial_wc)
    initial_ww = result.get('initial_window_width', expected_initial_ww)
    current_wc = result.get('current_window_center', initial_wc)
    current_ww = result.get('current_window_width', initial_ww)

    if wl_changed:
        criteria_met += 1
        feedback_parts.append(f"W/L changed: WC={current_wc}, WW={current_ww}")
    else:
        # Check if values differ from initial
        wc_diff = abs(current_wc - initial_wc) > 5
        ww_diff = abs(current_ww - initial_ww) > 10
        if wc_diff or ww_diff:
            criteria_met += 1
            feedback_parts.append(f"W/L values changed: WC={current_wc}, WW={current_ww}")
        else:
            feedback_parts.append("W/L not detected as changed")

    # Criterion 3: Screenshot difference (image display changed)
    screenshot_diff = float(result.get('screenshot_diff', 0))
    if screenshot_diff > 50:  # Significant visual change
        criteria_met += 1
        feedback_parts.append(f"Visual change detected (diff={screenshot_diff:.0f})")
    elif screenshot_diff > 10:  # Some change
        criteria_met += 0.5
        feedback_parts.append(f"Minor visual change (diff={screenshot_diff:.0f})")
    else:
        feedback_parts.append("No significant visual change detected")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 66  # Pass if 2 out of 3 criteria met

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
