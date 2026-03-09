#!/usr/bin/env python3
"""
Verifier for trust_safety_reviewer_suspension task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trust_safety_suspension(traj, env_info, task_info):
    """
    Verify schema updates, user suspensions, and audit logging.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []
    
    schema = result.get('schema', {})
    data = result.get('data', {})
    logs = result.get('logs', {})

    # 1. Schema Validation (30 points total)
    # Check AccountStatus property (10 pts)
    if schema.get('has_account_status'):
        score += 10
        feedback.append("Schema: 'AccountStatus' property added to Profiles (+10)")
    else:
        # Fallback: if data shows they updated the field even if not in schema (schemaless)
        if data.get('bot_alpha_status') is not None:
            score += 10
            feedback.append("Schema: 'AccountStatus' property used (schemaless mode) (+10)")
        else:
            feedback.append("Schema: 'AccountStatus' property MISSING on Profiles")

    # Check Log Classes (10 + 10 pts)
    if schema.get('has_suspension_log_class'):
        score += 10
        feedback.append("Schema: 'SuspensionLog' class created (+10)")
    else:
        feedback.append("Schema: 'SuspensionLog' class MISSING")

    if schema.get('has_edge_class'):
        score += 10
        feedback.append("Schema: 'HasSuspensionLog' edge class created (+10)")
    else:
        feedback.append("Schema: 'HasSuspensionLog' edge class MISSING")

    # 2. Suspension Logic (40 points total)
    # Bot Alpha (3 bad reviews) -> Should be Suspended (15 pts)
    alpha_status = data.get('bot_alpha_status')
    if alpha_status == 'Suspended':
        score += 15
        feedback.append("Data: Bot Alpha (3 bad reviews) correctly suspended (+15)")
    else:
        feedback.append(f"Data: Bot Alpha status is '{alpha_status}', expected 'Suspended'")

    # Bot Beta (4 bad reviews) -> Should be Suspended (15 pts)
    beta_status = data.get('bot_beta_status')
    if beta_status == 'Suspended':
        score += 15
        feedback.append("Data: Bot Beta (4 bad reviews) correctly suspended (+15)")
    else:
        feedback.append(f"Data: Bot Beta status is '{beta_status}', expected 'Suspended'")

    # Innocent User (2 bad reviews) -> Should NOT be Suspended (10 pts)
    innocent_status = data.get('innocent_status')
    if innocent_status != 'Suspended':
        score += 10
        feedback.append("Data: Innocent user (2 bad reviews) safe (+10)")
    else:
        feedback.append("Data: Innocent user was INCORRECTLY suspended")

    # 3. Audit Log Validation (30 points total)
    # Check if bots are linked to a log with Reason="Review Bombing"
    
    # Bot Alpha Log
    alpha_reasons = logs.get('bot_alpha_reasons', [])
    if alpha_reasons and 'Review Bombing' in alpha_reasons:
        score += 15
        feedback.append("Log: Bot Alpha linked to 'Review Bombing' log (+15)")
    elif alpha_reasons:
        score += 10
        feedback.append(f"Log: Bot Alpha linked to log but wrong reason: {alpha_reasons} (+10)")
    else:
        feedback.append("Log: Bot Alpha has NO log entry linked")

    # Bot Beta Log
    beta_reasons = logs.get('bot_beta_reasons', [])
    if beta_reasons and 'Review Bombing' in beta_reasons:
        score += 15
        feedback.append("Log: Bot Beta linked to 'Review Bombing' log (+15)")
    elif beta_reasons:
        score += 10
        feedback.append(f"Log: Bot Beta linked to log but wrong reason: {beta_reasons} (+10)")
    else:
        feedback.append("Log: Bot Beta has NO log entry linked")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }