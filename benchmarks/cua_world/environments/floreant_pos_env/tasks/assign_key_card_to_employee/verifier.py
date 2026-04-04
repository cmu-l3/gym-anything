#!/usr/bin/env python3
"""
Verifier for assign_key_card_to_employee task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_key_card_to_employee(traj, env_info, task_info):
    """
    Verify that the employee John Doe has the correct secret key assigned.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    target_key = "9876543210"
    
    # Load result from container
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

    # Extract DB results
    db_result = result.get('db_result', {})
    user_found = db_result.get('user_found', False)
    actual_key = db_result.get('actual_key', "")
    app_running = result.get('app_was_running', False)

    score = 0
    feedback = []

    # Criterion 1: App was running (10 pts)
    if app_running:
        score += 10
        feedback.append("Floreant POS was running.")
    else:
        feedback.append("Floreant POS was NOT running at end of task.")

    # Criterion 2: User found in DB (20 pts)
    if user_found:
        score += 20
        feedback.append("User 'John Doe' found in database.")
    else:
        feedback.append("User 'John Doe' NOT found in database.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 3: Key matches (70 pts)
    if actual_key == target_key:
        score += 70
        feedback.append(f"Secret Key correctly set to '{target_key}'.")
    elif actual_key:
        feedback.append(f"Secret Key set to incorrect value: '{actual_key}' (Expected: '{target_key}').")
    else:
        feedback.append("Secret Key was empty.")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }