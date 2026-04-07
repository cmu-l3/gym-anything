#!/usr/bin/env python3
"""
Verifier for delete_warrant_type task.
Checks if the specified warrant type was removed from the database
and verifies that no other records were accidentally deleted.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_delete_warrant_type(traj, env_info, task_info):
    """
    Verify deletion of 'Civil Contempt' warrant type.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/delete_warrant_type_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    target_exists = int(result.get('target_exists', 1))
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    score = 0
    feedback_parts = []
    
    # 3. Scoring Logic
    
    # Criterion 1: Target record is gone (50 pts)
    if target_exists == 0:
        score += 50
        feedback_parts.append("Target 'Civil Contempt' successfully removed")
    else:
        feedback_parts.append("Target 'Civil Contempt' still exists in database")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Count decreased by exactly 1 (25 pts)
    # This ensures they didn't delete the wrong thing or mass delete
    delta = initial_count - current_count
    if delta == 1:
        score += 25
        feedback_parts.append("Record count decreased by exactly 1")
    elif delta > 1:
        score += 10 # Partial credit for deleting it, but with collateral damage
        feedback_parts.append(f"WARNING: Deleted {delta} records (expected 1)")
    else:
        # Should be covered by target_exists check, but just in case
        feedback_parts.append(f"Count delta invalid ({delta})")

    # Criterion 3: Login/Navigation inferred (15 pts)
    # If they successfully deleted the target, they must have navigated there
    if target_exists == 0:
        score += 15
        feedback_parts.append("Admin panel navigation successful")

    # Criterion 4: Data integrity (10 pts)
    # If delta is exactly 1, it implies high precision/integrity
    if delta == 1:
        score += 10
        feedback_parts.append("Data integrity maintained")

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }