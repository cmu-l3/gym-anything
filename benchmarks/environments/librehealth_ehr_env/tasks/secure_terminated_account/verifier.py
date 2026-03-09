#!/usr/bin/env python3
"""
Verifier for secure_terminated_account task.

Scoring Criteria:
1. Account Deactivated (active=0): 40 points
2. Provider Privileges Revoked (authorized=0): 30 points
3. Password Updated Correctly: 30 points

Pass Threshold: 100 points (Security tasks usually require full compliance)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_account(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check User Existence
    if not result.get("user_found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User 'ghouse' was deleted or not found. Account must be secured, not deleted."
        }

    # 2. Check Active Status (40 pts)
    active_status = result.get("active", -1)
    if active_status == 0:
        score += 40
        feedback.append("Account deactivated (Pass)")
    else:
        feedback.append(f"Account still active (Fail, active={active_status})")

    # 3. Check Authorized/Provider Status (30 pts)
    auth_status = result.get("authorized", -1)
    if auth_status == 0:
        score += 30
        feedback.append("Provider status revoked (Pass)")
    else:
        feedback.append(f"Provider status still active (Fail, authorized={auth_status})")

    # 4. Check Password (30 pts)
    if result.get("password_valid", False):
        score += 30
        feedback.append("Password updated correctly (Pass)")
    else:
        feedback.append("Password does not match required value (Fail)")

    # 5. Check Anti-Gaming / VLM (Optional boost or validation)
    # For this strict security task, programmtic verification is primary.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }