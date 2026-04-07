#!/usr/bin/env python3
"""
Verifier for update_work_package_schedule task.

Checks:
1. Work package found.
2. Modified AFTER task start (anti-gaming).
3. Start Date matches expected.
4. Due Date matches expected.
5. Estimated Hours matches expected.
6. % Complete matches expected.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata
    metadata = task_info.get('metadata', {})
    expected_start = metadata.get('expected_start_date', '2025-09-01')
    expected_due = metadata.get('expected_due_date', '2025-10-15')
    expected_hours = float(metadata.get('expected_estimated_hours', 40.0))
    expected_ratio = int(metadata.get('expected_done_ratio', 25))

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if WP was found/query successful
    if not result.get('found', False) or result.get('error'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not find target work package in database. Error: {result.get('error', 'Unknown')}"
        }

    score = 0
    feedback_parts = []
    
    # Anti-gaming: Check timestamp
    task_start = int(result.get('task_start_timestamp', 0))
    wp_updated_at = int(result.get('updated_at', 0))

    if wp_updated_at <= task_start:
        feedback_parts.append("Work package was NOT modified during the task (timestamp check failed).")
        # We continue to show what values were wrong, but this is critical failure for scoring usually
        # However, we will just penalize heavily or fail.
        # Let's count it as 0 score for actions if not modified.
        return {
            "passed": False,
            "score": 0,
            "feedback": "Work package was not modified during the task session. " + " | ".join(feedback_parts)
        }
    else:
        feedback_parts.append("Work package modification detected.")

    # 1. Start Date (25 pts)
    actual_start = result.get('start_date')
    if actual_start == expected_start:
        score += 25
        feedback_parts.append(f"Start date correct ({actual_start})")
    else:
        feedback_parts.append(f"Start date mismatch: expected {expected_start}, got {actual_start}")

    # 2. Due Date (25 pts)
    actual_due = result.get('due_date')
    if actual_due == expected_due:
        score += 25
        feedback_parts.append(f"Due date correct ({actual_due})")
    else:
        feedback_parts.append(f"Due date mismatch: expected {expected_due}, got {actual_due}")

    # 3. Estimated Hours (25 pts)
    actual_hours = result.get('estimated_hours')
    # Handle None or conversion
    try:
        if actual_hours is not None and abs(float(actual_hours) - expected_hours) < 0.1:
            score += 25
            feedback_parts.append(f"Estimated hours correct ({expected_hours})")
        else:
            feedback_parts.append(f"Estimated hours mismatch: expected {expected_hours}, got {actual_hours}")
    except (TypeError, ValueError):
        feedback_parts.append(f"Estimated hours invalid: {actual_hours}")

    # 4. Done Ratio (25 pts)
    actual_ratio = result.get('done_ratio')
    try:
        if actual_ratio is not None and int(actual_ratio) == expected_ratio:
            score += 25
            feedback_parts.append(f"% Complete correct ({expected_ratio}%)")
        else:
            feedback_parts.append(f"% Complete mismatch: expected {expected_ratio}, got {actual_ratio}")
    except (TypeError, ValueError):
        feedback_parts.append(f"% Complete invalid: {actual_ratio}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }