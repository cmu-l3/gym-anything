#!/usr/bin/env python3
"""
Verifier for deactivate_user_account task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_user_account(traj, env_info, task_info):
    """
    Verify that user 'jdoe' was deactivated but not deleted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Data extraction
    jdoe_exists = int(result.get("jdoe_exists", 0))
    jdoe_active = result.get("jdoe_active", "1") # Default to 1 (active) if missing
    admin_active = result.get("admin_active", "0")

    # Criterion A: User must still exist (30 pts)
    # If the agent deleted the user instead of deactivating, this fails.
    if jdoe_exists > 0:
        score += 30
        feedback_parts.append("User 'jdoe' record preserved")
    else:
        feedback_parts.append("CRITICAL: User 'jdoe' was DELETED from database")
        return {"passed": False, "score": 0, "feedback": "User was deleted instead of deactivated"}

    # Criterion B: User must be inactive (50 pts)
    # In SQL, 'active' is often 1/0 or 'y'/'n'. Adjust logic to handle types.
    is_inactive = False
    if str(jdoe_active) in ["0", "n", "false", ""]:
        is_inactive = True
        score += 50
        feedback_parts.append("User 'jdoe' successfully deactivated")
    else:
        feedback_parts.append(f"User 'jdoe' is still active (status: {jdoe_active})")

    # Criterion C: Admin safety check (20 pts)
    # Ensure the agent didn't deactivate the wrong user (the admin).
    if str(admin_active) in ["1", "y", "true"]:
        score += 20
        feedback_parts.append("Admin account remains active")
    else:
        feedback_parts.append("WARNING: Admin account was deactivated!")

    # 3. Final Assessment
    # Strict pass: Must exist AND be inactive AND admin safe
    passed = (jdoe_exists > 0) and is_inactive and (str(admin_active) in ["1", "y", "true"])
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }