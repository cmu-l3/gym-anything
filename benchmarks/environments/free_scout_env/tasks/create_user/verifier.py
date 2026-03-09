#!/usr/bin/env python3
"""Verifier for create_user task."""

import json
import tempfile
import os


def verify_create_user(traj, env_info, task_info):
    """Verify that a new user (support agent) was created in FreeScout."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_first = metadata.get('expected_first_name', 'Rebecca')
    expected_last = metadata.get('expected_last_name', 'Fleming')
    expected_email = metadata.get('expected_email', 'rebecca.fleming@helpdesk.local')

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

    score = 0
    feedback_parts = []

    # Criterion 1: User count increased (15 points)
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"User count increased: {initial_count} -> {current_count}")
    else:
        feedback_parts.append(f"User count unchanged: {initial_count} -> {current_count}")

    # Criterion 2: User found in database (15 points)
    user_found = result.get('user_found', False)
    if user_found:
        score += 15
        feedback_parts.append("User found in database")
    else:
        feedback_parts.append("User NOT found in database")

    # Criterion 3: First name matches (15 points)
    actual_first = result.get('user_first_name', '').strip()
    if actual_first.lower() == expected_first.lower():
        score += 15
        feedback_parts.append(f"First name matches: '{actual_first}'")
    elif expected_first.lower() in actual_first.lower():
        score += 7
        feedback_parts.append(f"First name partial match: '{actual_first}'")
    else:
        feedback_parts.append(f"First name mismatch: expected '{expected_first}', got '{actual_first}'")

    # Criterion 4: Last name matches (15 points)
    actual_last = result.get('user_last_name', '').strip()
    if actual_last.lower() == expected_last.lower():
        score += 15
        feedback_parts.append(f"Last name matches: '{actual_last}'")
    elif expected_last.lower() in actual_last.lower():
        score += 7
        feedback_parts.append(f"Last name partial match: '{actual_last}'")
    else:
        feedback_parts.append(f"Last name mismatch: expected '{expected_last}', got '{actual_last}'")

    # Criterion 5: Email matches (25 points)
    actual_email = result.get('user_email', '').strip()
    if actual_email.lower() == expected_email.lower():
        score += 25
        feedback_parts.append(f"Email matches: '{actual_email}'")
    elif actual_email:
        score += 5
        feedback_parts.append(f"Email set but mismatch: expected '{expected_email}', got '{actual_email}'")
    else:
        feedback_parts.append("Email not set")

    # Criterion 6: Role is 'user' (regular agent, not admin) (15 points)
    actual_role = result.get('user_role', '').strip().lower()
    if actual_role == 'user':
        score += 15
        feedback_parts.append("Role correctly set to 'user'")
    elif actual_role == 'admin':
        score += 5
        feedback_parts.append("Role is 'admin' instead of 'user'")
    elif actual_role:
        feedback_parts.append(f"Unexpected role: '{actual_role}'")
    else:
        feedback_parts.append("Role not found in export")

    passed = score >= 70 and user_found and current_count > initial_count

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
