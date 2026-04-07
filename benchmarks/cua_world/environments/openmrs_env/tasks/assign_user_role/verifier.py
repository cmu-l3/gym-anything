#!/usr/bin/env python3
"""
Verifier for assign_user_role task.
Checks if the target user has the specific role assigned via REST API data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_user_role(traj, env_info, task_info):
    """
    Verifies that the user 'nurse_betty' was assigned the 'Organizational Doctor' role.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    target_role = metadata.get('target_role', 'Organizational Doctor')
    target_username = metadata.get('target_username', 'nurse_betty')

    # Copy result file
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

    # Verification Logic
    score = 0
    feedback_parts = []
    
    user_found = result.get('user_found', False)
    has_target_role = result.get('has_target_role', False)
    found_username = result.get('username', '')
    is_retired = result.get('is_retired', False)

    # Criterion 1: User still exists and is correct (20 pts)
    if user_found and found_username == target_username:
        score += 20
        feedback_parts.append(f"User '{target_username}' found")
    else:
        return {"passed": False, "score": 0, "feedback": "Target user not found or deleted"}

    # Criterion 2: Account is active (not retired) (10 pts)
    if not is_retired:
        score += 10
        feedback_parts.append("Account is active")
    else:
        feedback_parts.append("Warning: Account was retired/deleted")

    # Criterion 3: Role assigned (70 pts)
    if has_target_role:
        score += 70
        feedback_parts.append(f"Role '{target_role}' successfully assigned")
    else:
        feedback_parts.append(f"Role '{target_role}' NOT found in user roles: {result.get('roles_found', [])}")

    # Pass Threshold
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }