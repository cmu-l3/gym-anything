#!/usr/bin/env python3
"""
Verifier for Create RBAC Read-Only User task.
Scores the agent based on the existence and correct configuration
of Wazuh RBAC policies, roles, and users.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_rbac_readonly_user(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Criteria
    score = 0
    feedback = []

    # 1. Policy checks (30 pts)
    if result.get("policy_exists"):
        score += 15
        feedback.append("Policy 'readonly_agents' created")
        if result.get("policy_correct"):
            score += 15
            feedback.append("Policy permissions correct")
        else:
            feedback.append("Policy permissions incorrect (check actions/resources)")
    else:
        feedback.append("Policy 'readonly_agents' not found")

    # 2. Role checks (15 pts)
    if result.get("role_exists"):
        score += 15
        feedback.append("Role 'soc_analyst_readonly' created")
    else:
        feedback.append("Role 'soc_analyst_readonly' not found")

    # 3. Policy-Role Link (15 pts)
    if result.get("policy_linked_to_role"):
        score += 15
        feedback.append("Policy linked to role correctly")
    else:
        feedback.append("Policy not linked to role")

    # 4. User checks (15 pts)
    if result.get("user_exists"):
        score += 15
        feedback.append("User 'analyst_jsmith' created")
    else:
        feedback.append("User 'analyst_jsmith' not found")

    # 5. Role-User Link (15 pts)
    if result.get("role_assigned_to_user"):
        score += 15
        feedback.append("Role assigned to user correctly")
    else:
        feedback.append("Role not assigned to user")

    # 6. Authentication Check (5 pts)
    if result.get("authentication_success"):
        score += 5
        feedback.append("New user authentication successful")
    else:
        feedback.append("New user authentication failed")

    # 7. Verification File (5 pts)
    if result.get("verification_file_exists"):
        score += 5
        feedback.append("Verification file saved")
    else:
        feedback.append("Verification file missing")

    # Pass logic
    passed = score >= 70 and result.get("policy_linked_to_role") and result.get("role_assigned_to_user")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }