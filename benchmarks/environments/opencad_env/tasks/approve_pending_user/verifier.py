#!/usr/bin/env python3
"""Verifier for approve_pending_user task."""

import json
import tempfile
import os


def verify_approve_pending_user(traj, env_info, task_info):
    """Verify that the pending user Sarah Mitchell was approved."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_user_name', 'Sarah Mitchell').lower()
    expected_email = metadata.get('expected_user_email', 'sarah.mitchell@opencad.local').lower()

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/approve_pending_user_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    sarah = result.get('sarah_mitchell', {})

    # Check 1: Sarah Mitchell exists in database (10 pts)
    sarah_name = (sarah.get('name') or '').strip().lower()
    if expected_name in sarah_name or sarah_name in expected_name:
        score += 10
        feedback_parts.append("Sarah Mitchell found in database")
    else:
        feedback_parts.append(f"Sarah Mitchell not found, got: '{sarah_name}'")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}

    # Check 2: Sarah's approved status changed to 1 (40 pts - main check)
    approved_str = str(sarah.get('approved', '0')).strip()
    if approved_str == '1':
        score += 40
        feedback_parts.append("Sarah Mitchell is now approved")
    else:
        feedback_parts.append(f"Sarah Mitchell NOT approved (status={approved_str})")

    # Check 3: Approved count increased (20 pts)
    initial_approved = result.get('initial_approved_count', 0)
    current_approved = result.get('current_approved_count', 0)
    if current_approved > initial_approved:
        score += 20
        feedback_parts.append(f"Approved user count increased: {initial_approved} -> {current_approved}")
    else:
        feedback_parts.append(f"Approved count unchanged: {initial_approved} -> {current_approved}")

    # Check 4: Pending count decreased (20 pts)
    initial_pending = result.get('initial_pending_count', 0)
    current_pending = result.get('current_pending_count', 0)
    if current_pending < initial_pending:
        score += 20
        feedback_parts.append(f"Pending user count decreased: {initial_pending} -> {current_pending}")
    else:
        feedback_parts.append(f"Pending count unchanged: {initial_pending} -> {current_pending}")

    # Check 5: Department assignment (10 pts)
    dept = (sarah.get('department') or '').strip()
    if dept:
        score += 10
        feedback_parts.append(f"Department assigned: {dept}")
    else:
        feedback_parts.append("No department assignment found")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }
