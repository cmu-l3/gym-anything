#!/usr/bin/env python3
"""
Verifier for correct_misfiled_time_entry task.

Verifies:
1. The original TimeEntry (tracked by ID) still exists.
2. It is now associated with the 'Security Audit' work package.
3. The hours (4.0) have not been changed.
4. The comments ('External security analysis') have not been changed.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_misfiled_time_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Scoring
    score = 0
    max_score = 100
    feedback_parts = []

    # Check existence
    if not result.get('found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "The time entry was deleted or could not be found by its original ID. You should edit the existing entry, not delete and recreate it."
        }
    
    score += 20
    feedback_parts.append("Time entry exists")

    # Check Work Package
    actual_wp = result.get('work_package_subject', '')
    expected_wp = "Security Audit"
    
    if actual_wp == expected_wp:
        score += 40
        feedback_parts.append(f"Correctly reassigned to '{expected_wp}'")
    else:
        feedback_parts.append(f"Incorrect Work Package: '{actual_wp}' (expected '{expected_wp}')")

    # Check Hours
    actual_hours = float(result.get('hours', 0.0))
    expected_hours = 4.0
    
    if abs(actual_hours - expected_hours) < 0.01:
        score += 20
        feedback_parts.append("Hours preserved (4.0)")
    else:
        feedback_parts.append(f"Hours changed to {actual_hours}")

    # Check Comments
    actual_comment = result.get('comments', '').strip()
    expected_comment = "External security analysis"
    
    if actual_comment == expected_comment:
        score += 20
        feedback_parts.append("Comment preserved")
    else:
        feedback_parts.append(f"Comment changed to '{actual_comment}'")

    passed = (score == max_score)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }