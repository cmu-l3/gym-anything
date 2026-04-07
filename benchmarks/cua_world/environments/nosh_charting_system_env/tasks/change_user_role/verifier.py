#!/usr/bin/env python3
"""
Verifier for change_user_role task in NOSH ChartingSystem.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_user_role(traj, env_info, task_info):
    """
    Verifies that the user 'demo_provider' was promoted to Administrator.
    
    Expected Final State:
    - users.group_id for 'demo_provider' should be 1 (Administrator).
    - User should still exist (not deleted).
    """
    
    # 1. Setup Interface
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Data
    initial_group = int(result.get("initial_group_id", -1))
    final_group = int(result.get("final_group_id", -1))
    user_exists = result.get("user_exists", False)
    final_username = result.get("final_username", "")
    
    # Metadata targets
    TARGET_GROUP_ID = 1  # Administrator
    TARGET_USERNAME = "demo_provider"

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    passed = False

    # Check 1: User Integrity (20 pts)
    if user_exists and final_username == TARGET_USERNAME:
        score += 20
        feedback_parts.append("Target user account preserved.")
    else:
        feedback_parts.append("Target user account was deleted or modified incorrectly.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 2: Role Change (80 pts)
    if final_group == TARGET_GROUP_ID:
        score += 80
        feedback_parts.append("User successfully promoted to Administrator.")
        passed = True
    elif final_group == initial_group:
        feedback_parts.append("User role was not changed (still Provider).")
    else:
        feedback_parts.append(f"User role changed to unexpected ID: {final_group} (Expected: {TARGET_GROUP_ID}).")

    # Anti-gaming: Ensure it actually changed
    if passed and final_group == initial_group:
        # This shouldn't happen due to logic above, but failsafe
        passed = False
        score = 0
        feedback_parts.append("Logic Error: Final group matches initial group despite target match.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }