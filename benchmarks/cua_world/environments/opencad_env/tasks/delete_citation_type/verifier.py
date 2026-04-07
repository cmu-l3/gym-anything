#!/usr/bin/env python3
"""Verifier for delete_citation_type task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_citation_type(traj, env_info, task_info):
    """
    Verify that the 'Unsecured Excavation' citation type was deleted.
    
    Criteria:
    1. The specific record must NOT exist in the database.
    2. The total count of records must have decreased by exactly 1.
    3. Other records must still exist (prevents 'delete all' gaming).
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/delete_citation_type_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    target_exists = result.get('target_exists', True)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    others_count = result.get('others_count', 0)

    # Criterion 1: Record Deleted (40 pts)
    if not target_exists:
        score += 40
        feedback_parts.append("Target citation type successfully removed.")
    else:
        feedback_parts.append("Target citation type still exists in database.")

    # Criterion 2: Count Check (30 pts)
    # Count should decrease by exactly 1
    expected_count = initial_count - 1
    if current_count == expected_count:
        score += 30
        feedback_parts.append(f"Record count decreased by 1 ({initial_count} -> {current_count}).")
    else:
        feedback_parts.append(f"Incorrect record count change. Initial: {initial_count}, Final: {current_count}.")

    # Criterion 3: Safety/Anti-gaming Check (30 pts)
    # Ensure they didn't just truncate the table. 
    # We expect at least 3 distractors to remain (Speeding, Parking, Reckless).
    if others_count >= 3:
        score += 30
        feedback_parts.append("Other citation types remain intact.")
    else:
        feedback_parts.append(f"Warning: Other citation types missing (Found {others_count}). Possible table wipe.")

    # Pass threshold
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }