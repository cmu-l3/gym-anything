#!/usr/bin/env python3
"""Verifier for View Metadata task"""

import sys
import os
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))


def verify_view_metadata(traj, env_info, task_info):
    """Verify that DICOM metadata was viewed."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 2
    feedback_parts = []

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

    # Criterion 2: Metadata panel was opened
    metadata_visible = result.get('metadata_visible', False)
    screenshot_diff = float(result.get('screenshot_diff', 0))

    if metadata_visible:
        criteria_met += 1
        feedback_parts.append("Metadata panel opened")
    elif screenshot_diff > 300:
        # Significant UI change suggests panel was opened
        criteria_met += 1
        feedback_parts.append("UI change detected (metadata panel likely opened)")
    else:
        feedback_parts.append("Metadata panel not detected")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
