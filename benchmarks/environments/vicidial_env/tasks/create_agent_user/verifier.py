#!/usr/bin/env python3
"""
Verifier for create_agent_user task.

Checks if the user '2001' was created in the Vicidial database with the correct settings.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_agent_user(traj, env_info, task_info):
    """
    Verify that the agent user was created with correct parameters.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    weights = metadata.get('scoring_weights', {})

    # Load result from container
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
    max_score = sum(weights.values())
    feedback_parts = []
    
    # 1. Check if user exists
    user_exists = result.get('user_exists', False)
    user_data = result.get('user_data', {})
    
    if not user_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User '2001' was not found in the Vicidial database."
        }
    
    score += weights.get('exists', 10)
    feedback_parts.append("User 2001 created")

    # 2. Check each field
    # Helper to check fields case-insensitively where appropriate
    def check_field(field_key, display_name):
        nonlocal score
        actual_val = str(user_data.get(field_key, "")).strip()
        expected_val = str(expected.get(field_key, "")).strip()
        weight = weights.get(field_key, 0)
        
        # Exact match required for passwords and IDs
        if actual_val == expected_val:
            score += weight
            return True
        else:
            feedback_parts.append(f"Incorrect {display_name}: expected '{expected_val}', got '{actual_val}'")
            return False

    check_field('pass', 'Password')
    check_field('full_name', 'Full Name')
    check_field('user_level', 'User Level')
    check_field('user_group', 'User Group')
    check_field('active', 'Active Status')
    check_field('phone_login', 'Phone Login')
    check_field('phone_pass', 'Phone Password')
    check_field('hotkeys_active', 'Hotkeys Active')
    check_field('scheduled_callbacks', 'Scheduled Callbacks')

    # 3. Anti-gaming check: confirm it's a NEW record
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    
    if final_count <= initial_count:
        feedback_parts.append("WARNING: User count did not increase (modified existing user?)")
        # We don't fail strictly here because they might have deleted another user, 
        # but combined with the specific ID check, it's likely fine.
    
    # Calculate final result
    # Pass threshold is 60 as defined in task description
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }