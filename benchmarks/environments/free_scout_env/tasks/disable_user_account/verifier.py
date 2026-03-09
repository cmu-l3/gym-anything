#!/usr/bin/env python3
"""Verifier for disable_user_account task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_user_account(traj, env_info, task_info):
    """
    Verify that the user account was disabled but NOT deleted.
    
    Expected outcomes:
    1. User record 'marcus.webb@helpdesk.local' must still exist.
    2. User status should be 2 (Disabled) [1 is Active].
    3. Admin account should still be Active (no self-lockout).
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_status = str(metadata.get('expected_status', '2'))  # 2 = Disabled
    active_status = str(metadata.get('active_status', '1'))      # 1 = Active

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

    score = 0
    feedback_parts = []
    
    # Extract data
    target_found = result.get('target_found', False)
    current_status = str(result.get('current_status', '')).strip()
    initial_status = str(result.get('initial_status', '')).strip()
    record_deleted = result.get('record_deleted', False)
    
    current_admin_status = str(result.get('current_admin_status', '')).strip()
    initial_admin_status = str(result.get('initial_admin_status', '')).strip()

    # --- Criterion 1: User record must still exist (20 points) ---
    if target_found and not record_deleted:
        score += 20
        feedback_parts.append("User record preserved")
    else:
        feedback_parts.append("FAIL: User record was deleted or not found")
        # If user is deleted, they technically are disabled, but it violates specific instructions
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User record was deleted instead of disabled. Task requires preserving the record."
        }

    # --- Criterion 2: Status is Disabled (50 points) ---
    if current_status == expected_status:
        score += 50
        feedback_parts.append("User status is Disabled")
    elif current_status == active_status:
        feedback_parts.append("FAIL: User status is still Active")
    else:
        feedback_parts.append(f"User status is unknown/unexpected ({current_status})")

    # --- Criterion 3: State Change Detected (15 points) ---
    # Anti-gaming: ensure the status actually changed during the task
    if initial_status == active_status and current_status == expected_status:
        score += 15
        feedback_parts.append("Status change confirmed")
    elif initial_status == current_status:
        feedback_parts.append("No change in status detected")

    # --- Criterion 4: Admin Safety Check (15 points) ---
    # Ensure they didn't disable the admin account by mistake
    if current_admin_status == initial_admin_status and current_admin_status == active_status:
        score += 15
        feedback_parts.append("Admin account remains active")
    else:
        feedback_parts.append("FAIL: Admin account was modified or disabled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }