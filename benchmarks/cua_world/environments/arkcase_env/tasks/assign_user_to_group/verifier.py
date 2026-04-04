#!/usr/bin/env python3
"""
Verifier for assign_user_to_group task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_user_to_group(traj, env_info, task_info):
    """
    Verify that the user was assigned to the group.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    target_user = result.get('target_user', 'Unknown')
    target_group = result.get('target_group', 'Unknown')

    # Criterion 1: LDAP Membership (60 points) - HIGH FIDELITY
    if result.get('ldap_confirmed', False):
        score += 60
        feedback_parts.append(f"User '{target_user}' successfully added to group '{target_group}' in LDAP.")
    else:
        feedback_parts.append(f"User '{target_user}' NOT found in group '{target_group}' in LDAP.")

    # Criterion 2: API Reflection (30 points)
    if result.get('api_confirmed', False):
        score += 30
        feedback_parts.append("Change reflected in ArkCase API.")
    else:
        feedback_parts.append("Change NOT yet reflected in ArkCase API (or sync pending).")

    # Criterion 3: User Integrity (10 points)
    if result.get('user_exists', False):
        score += 10
        feedback_parts.append("User account remains valid.")
    else:
        feedback_parts.append("CRITICAL: User account seems to have been deleted.")

    # Pass/Fail determination
    # Must have at least LDAP confirmation to pass
    passed = (result.get('ldap_confirmed', False) is True)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }