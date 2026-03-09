#!/usr/bin/env python3
"""
Verifier for assign_user_role task.

Criteria:
1. User 'jwilson' exists and is active (not retired).
2. User UUID matches the one created during setup (Anti-gaming: prevents delete/recreate).
3. User has the 'System Developer' role.
4. User retains the baseline 'Provider' role (demonstrates editing rather than overwriting).
5. VLM verification of the trajectory (optional but valuable).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_user_role(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_role = metadata.get('target_role', 'System Developer')
    baseline_role = metadata.get('required_baseline_role', 'Provider')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    api_result = result.get("api_result", {})
    original_uuid = result.get("original_uuid", "")
    
    current_uuid = api_result.get("current_uuid", "")
    user_found = api_result.get("user_found", False)
    retired = api_result.get("retired", False)
    roles = api_result.get("roles", [])

    feedback_parts = []
    score = 0
    
    # Check 1: User Integrity (30 pts)
    # Must exist, match original UUID (no delete/recreate), and be active
    if user_found and not retired:
        if current_uuid == original_uuid:
            score += 30
            feedback_parts.append("User account integrity verified (UUID match).")
        else:
            feedback_parts.append("FAIL: User UUID changed! Account was likely deleted and recreated.")
            return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: User was recreated instead of edited."}
    else:
        feedback_parts.append("FAIL: User 'jwilson' not found or is retired.")
        return {"passed": False, "score": 0, "feedback": "Target user not found."}

    # Check 2: Target Role (50 pts)
    if target_role in roles:
        score += 50
        feedback_parts.append(f"Success: '{target_role}' role added.")
    else:
        feedback_parts.append(f"FAIL: '{target_role}' role missing. Found: {roles}")

    # Check 3: Baseline Role Preservation (20 pts)
    # The user started with 'Provider'. It should still be there.
    if baseline_role in roles:
        score += 20
        feedback_parts.append(f"Baseline '{baseline_role}' role preserved.")
    else:
        feedback_parts.append(f"Warning: Baseline '{baseline_role}' role was removed.")
        # We penalize but don't fail completely if they at least added the new one
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }