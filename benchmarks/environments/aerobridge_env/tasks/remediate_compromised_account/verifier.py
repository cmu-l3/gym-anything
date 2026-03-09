#!/usr/bin/env python3
"""
Verifier for remediate_compromised_account task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remediate_compromised_account(traj, env_info, task_info):
    """
    Verify the agent correctly identified and deactivated the compromised account.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    victim = result.get('victim_username', 'unknown')
    victim_active = result.get('victim_is_active', True)
    innocents_active = result.get('innocent_users_active', True)
    admin_active = result.get('admin_active', True)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').strip()

    # CRITERION 1: Compromised User Deactivated (50 pts)
    if not victim_active:
        score += 50
        feedback_parts.append(f"SUCCESS: Compromised user '{victim}' was deactivated.")
    else:
        feedback_parts.append(f"FAIL: Compromised user '{victim}' is still Active.")

    # CRITERION 2: Innocent Users Protected (20 pts)
    # This prevents the agent from simply deactivating everyone.
    if innocents_active and admin_active:
        score += 20
        feedback_parts.append("SUCCESS: Innocent users and admin remain active.")
    else:
        feedback_parts.append("FAIL: Innocent users or admin were incorrectly deactivated.")

    # CRITERION 3: Report Created (10 pts)
    if report_exists:
        score += 10
        feedback_parts.append("SUCCESS: Incident report file created.")
    else:
        feedback_parts.append("FAIL: Incident report file not found.")

    # CRITERION 4: Correct Username in Report (20 pts)
    if report_exists and victim.lower() in report_content.lower():
        score += 20
        feedback_parts.append(f"SUCCESS: Report correctly identifies '{victim}'.")
    elif report_exists:
        feedback_parts.append(f"FAIL: Report contains '{report_content}', expected '{victim}'.")

    # Pass Threshold
    passed = (score >= 70) and (not victim_active)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }