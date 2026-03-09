#!/usr/bin/env python3
"""Verifier for Take Snapshot task"""

import sys
import os
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))


def verify_take_snapshot(traj, env_info, task_info):
    """Verify that a snapshot was exported."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    metadata = task_info.get('metadata', {})
    expected_formats = metadata.get('expected_formats', ['png', 'jpg', 'jpeg'])

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

    # Criterion 1: Export was found
    if result.get('found', False):
        criteria_met += 1
        feedback_parts.append("Export created")
    else:
        feedback_parts.append("No export found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Export file exists with valid size
    export_size = result.get('export_size', 0)
    if export_size > 1000:  # At least 1KB
        criteria_met += 1
        feedback_parts.append(f"Export size: {export_size} bytes")
    else:
        feedback_parts.append(f"Export too small: {export_size} bytes")

    # Criterion 3: File has correct format
    export_file = result.get('export_file', '')
    if export_file:
        ext = export_file.split('.')[-1].lower()
        if ext in expected_formats:
            criteria_met += 1
            feedback_parts.append(f"Format: {ext.upper()}")
        else:
            feedback_parts.append(f"Unexpected format: {ext}")
    else:
        feedback_parts.append("No export path")

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 66

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
