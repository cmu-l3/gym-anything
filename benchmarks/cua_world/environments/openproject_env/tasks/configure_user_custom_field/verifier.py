#!/usr/bin/env python3
"""
Verifier for configure_user_custom_field task.

Verifies:
1. A Custom Field named "Employee ID" exists.
2. It is a 'UserCustomField' type (not WorkPackageCustomField).
3. It has 'string' (Text) format.
4. User 'alice.johnson' has the value 'EMP-9901'.
5. The field was created during the task session.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_user_custom_field(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_value = metadata.get('expected_value', 'EMP-9901')

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_state = result.get('db_state', {})
    task_start = result.get('task_start', 0)

    score = 0
    feedback = []

    # Criterion 1: Custom Field Exists (30 pts)
    if db_state.get('field_exists'):
        score += 30
        feedback.append("Custom field 'Employee ID' exists.")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Custom field 'Employee ID' was not created."
        }

    # Criterion 2: Correct Scope/Type (20 pts)
    # Common mistake: Creating a WorkPackageCustomField instead of UserCustomField
    actual_type = db_state.get('field_type')
    if actual_type == 'UserCustomField':
        score += 20
        feedback.append("Field scope is correct (Users).")
    else:
        feedback.append(f"Incorrect field scope/type: {actual_type}. Expected 'UserCustomField'.")

    # Criterion 3: Correct Format (10 pts)
    actual_format = db_state.get('field_format')
    if actual_format == 'string':
        score += 10
        feedback.append("Field format is correct (Text).")
    else:
        feedback.append(f"Incorrect field format: {actual_format}. Expected 'string' (Text).")

    # Criterion 4: Anti-Gaming/Timing (Implicit in creation check, but good to verify)
    created_at = db_state.get('field_created_at', 0)
    if created_at >= task_start:
        feedback.append("Field was created during the task.")
    else:
        # If it existed before (cleanup failed?), penalize
        feedback.append("Warning: Field timestamp predates task start.")
        score = 0 # Fail if we detected stale state

    # Criterion 5: Data Entry (40 pts)
    user_val = db_state.get('user_value')
    if user_val == expected_value:
        score += 40
        feedback.append(f"User value correct: '{user_val}'.")
    else:
        feedback.append(f"User value incorrect. Expected '{expected_value}', found '{user_val}'.")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }