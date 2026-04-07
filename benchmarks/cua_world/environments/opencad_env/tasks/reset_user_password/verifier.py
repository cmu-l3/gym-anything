#!/usr/bin/env python3
"""
Verifier for reset_user_password task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reset_user_password(traj, env_info, task_info):
    """
    Verify that James Rodriguez's password was reset correctly.
    
    Criteria:
    1. User exists in database.
    2. Password hash validates against 'TemporaryPass2026!'.
    3. Password hash is different from the initial hash (change actually happened).
    4. User account is still active (approved=1).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task result
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
    
    verification = result.get('verification', {})
    initial_hash = result.get('initial_hash', '')
    
    # Criterion 1: User found (15 pts)
    if verification.get('found'):
        score += 15
        feedback_parts.append("Target user found")
    else:
        return {"passed": False, "score": 0, "feedback": "Target user 'James Rodriguez' not found in database"}

    # Criterion 2: Password Match (50 pts)
    # The export script runs password_verify() inside the PHP container
    if verification.get('password_match'):
        score += 50
        feedback_parts.append("Password updated correctly to target value")
    else:
        feedback_parts.append("Password does NOT match expected value 'TemporaryPass2026!'")

    # Criterion 3: Hash Changed (15 pts)
    # Protects against the unlikely case where the initial password was already the target
    current_hash = verification.get('current_hash', '')
    if current_hash != initial_hash and current_hash:
        score += 15
        feedback_parts.append("Password hash changed from initial state")
    elif current_hash == initial_hash:
        feedback_parts.append("Password hash unchanged (did nothing?)")
    
    # Criterion 4: Account Status (20 pts)
    # Ensure the user wasn't accidentally suspended or deleted during the edit
    approved = verification.get('approved', 0)
    if approved == 1:
        score += 20
        feedback_parts.append("User account remains active")
    else:
        feedback_parts.append(f"Warning: User account is not active/approved (status: {approved})")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }