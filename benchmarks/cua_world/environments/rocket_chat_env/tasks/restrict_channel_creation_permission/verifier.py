#!/usr/bin/env python3
"""
Verifier for restrict_channel_creation_permission task.

Checks:
1. 'user' role is NOT in 'create-c' permission (Primary Goal)
2. 'admin' role IS in 'create-c' permission (Safety)
3. Functional test confirms 'user' cannot create channels
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_channel_creation_permission(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    max_score = 100
    
    # Extract data
    current_roles = result.get("current_roles", [])
    functional_test = result.get("functional_test", {})
    creation_allowed = functional_test.get("creation_allowed")
    permissions_fetched = result.get("permissions_fetched", False)

    if not permissions_fetched:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to fetch permissions state from system."
        }

    # CRITERION 1: 'user' role removed (60 points)
    if "user" not in current_roles:
        score += 60
        feedback_parts.append("Success: 'user' role removed from create-c permission.")
    else:
        feedback_parts.append("Failure: 'user' role is STILL present in create-c permission.")

    # CRITERION 2: 'admin' role retained (20 points)
    if "admin" in current_roles:
        score += 20
        feedback_parts.append("Safety Check: 'admin' role retained.")
    else:
        feedback_parts.append("Safety Warning: 'admin' role was removed! Admins locked out.")

    # CRITERION 3: Functional Verification (20 points)
    # The export script attempts to create a channel as a regular user.
    # We expect creation_allowed to be "false".
    if creation_allowed == "false":
        score += 20
        feedback_parts.append("Functional Test: Verified regular user CANNOT create channels.")
    elif creation_allowed == "true":
        feedback_parts.append("Functional Test Failed: Regular user WAS able to create a channel.")
        # If functional test failed, we might want to penalize the first criterion too if it passed essentially by accident or gaming
        # But relying on the API check (Criterion 1) is usually robust enough.
    else:
        feedback_parts.append("Functional Test: Could not run verification.")

    passed = (score >= 80) # Needs User Removed (60) + Admin Kept (20) OR User Removed (60) + Functional (20)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }