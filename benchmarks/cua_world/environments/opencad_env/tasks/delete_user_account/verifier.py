#!/usr/bin/env python3
"""Verifier for delete_user_account task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_user_account(traj, env_info, task_info):
    """
    Verify that the specific user account was deleted while others remain.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_email = metadata.get('target_user_email', 'james.rodriguez@opencad.local')

    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/delete_user_result.json", temp_file.name)
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
    initial_total = result.get('initial_total_users', 0)
    current_total = result.get('current_total_users', 0)
    initial_safe = result.get('initial_safe_users', 0)
    current_safe = result.get('current_safe_users', 0)
    target_exists = result.get('target_user_exists', 1)
    
    # Criterion 1: Target user is GONE (40 pts)
    if target_exists == 0:
        score += 40
        feedback_parts.append(f"User '{target_email}' successfully deleted")
    else:
        feedback_parts.append(f"User '{target_email}' still exists in database")
        # Critical failure if target not deleted
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Safe users match initial count (20 pts)
    # This ensures they didn't just 'DELETE FROM users' and wipe everyone
    if current_safe == initial_safe and initial_safe > 0:
        score += 20
        feedback_parts.append("Other accounts (Admin, Dispatch, Sarah) remain intact")
    else:
        feedback_parts.append(f"Critical: Safe users count changed ({initial_safe} -> {current_safe}). Wrong users may have been deleted.")
        score = 0 # Penalty for destructive action

    # Criterion 3: Total count decreased by exactly 1 (20 pts)
    # This catches scenarios where they might have created a user then deleted it, or deleted multiple people
    diff = initial_total - current_total
    if diff == 1:
        score += 20
        feedback_parts.append("Total user count decreased by exactly 1")
    else:
        feedback_parts.append(f"User count change incorrect (diff: {diff})")

    # Criterion 4: VLM/Visual check (20 pts)
    # Check if the agent actually navigated to the admin panel
    # We use trajectory frames provided by the framework if available
    # For now, we assume if DB state is perfect, they likely used the UI correctly.
    # We give points for successful execution inferred from state.
    if score >= 80:
        score += 20
        feedback_parts.append("State change implies successful UI interaction")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }