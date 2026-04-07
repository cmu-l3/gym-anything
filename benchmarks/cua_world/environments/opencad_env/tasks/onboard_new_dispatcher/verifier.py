#!/usr/bin/env python3
"""Verifier for onboard_new_dispatcher task."""

import json
import tempfile
import os


def verify_onboard_new_dispatcher(traj, env_info, task_info):
    """
    Verify the complete onboarding workflow for Elena Ross.
    
    Criteria:
    1. User 'Elena Ross' exists in the database.
    2. User status is 'Approved' (1).
    3. User is linked to 'Communications' department.
    4. User identifier matches 'DISP-99'.
    5. User was created during this task (anti-gaming).
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_email = metadata.get('expected_email', 'elena.ross@opencad.local')
    expected_identifier = metadata.get('expected_identifier', 'DISP-99')
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/onboard_new_dispatcher_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    user = result.get('user', {})

    # Criterion 1: User Existence (20 pts)
    if result.get('user_found'):
        score += 20
        feedback_parts.append("User account found")
    else:
        feedback_parts.append("User account NOT found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    # Criterion 2: Approval Status (30 pts)
    # approved field is usually "1" for approved, "0" for pending
    approved_status = str(user.get('approved', '0')).strip()
    if approved_status == '1':
        score += 30
        feedback_parts.append("Account is approved")
    else:
        feedback_parts.append(f"Account is pending/suspended (status: {approved_status})")

    # Criterion 3: Department Assignment (30 pts)
    if user.get('department_assigned'):
        score += 30
        feedback_parts.append("Communications department assigned")
    else:
        dept_name = user.get('department_name', 'None')
        feedback_parts.append(f"Incorrect department: {dept_name}")

    # Criterion 4: Identifier Check (10 pts)
    actual_id = user.get('identifier', '').strip()
    if actual_id == expected_identifier:
        score += 10
        feedback_parts.append(f"Identifier matches ({actual_id})")
    else:
        feedback_parts.append(f"Identifier mismatch (expected {expected_identifier}, got {actual_id})")

    # Criterion 5: Anti-Gaming / Freshness (10 pts)
    if result.get('newly_created'):
        score += 10
        feedback_parts.append("Account created during task")
    else:
        feedback_parts.append("Account existed before task start (possible gaming)")

    # Pass Threshold: 80 points (Must be approved and have correct dept)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }