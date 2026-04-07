#!/usr/bin/env python3
"""Verifier for suspend_user_account task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_suspend_user_account(traj, env_info, task_info):
    """
    Verify that James Rodriguez's account was suspended with the correct reason.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_reason_keywords = metadata.get('expected_reason_keywords', ["misuse", "dispatch", "false calls"])
    # OpenCAD typically uses '2' for suspended, but sometimes 0. '2' is preferred for specific suspension.
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/suspend_user_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    james = result.get('james_rodriguez', {})
    admin = result.get('admin_user', {})
    initial_status = result.get('initial_status', '1')

    # Criterion 1: User found in DB (10 pts)
    if james.get('found'):
        score += 10
    else:
        return {"passed": False, "score": 0, "feedback": "Target user 'James Rodriguez' not found in database."}

    # Criterion 2: Status Changed from Initial (20 pts)
    current_status = str(james.get('approved_status', '')).strip()
    if current_status != str(initial_status):
        score += 20
        feedback_parts.append(f"Status changed (Initial: {initial_status}, Current: {current_status})")
    else:
        feedback_parts.append(f"Status did not change (Still {current_status})")

    # Criterion 3: Account is Suspended (approved = 2) (35 pts)
    # 2 is the standard 'Suspended' status in many OpenCAD versions. 
    # 0 is 'Pending'. If they set it to 0, it's partial credit as it disables access but isn't strictly 'Suspended'.
    if current_status == '2':
        score += 35
        feedback_parts.append("Account status set to 'Suspended' (2)")
    elif current_status == '0':
        score += 15
        feedback_parts.append("Account status set to 'Pending' (0) instead of 'Suspended'")
    else:
        feedback_parts.append(f"Account not suspended (Status: {current_status})")

    # Criterion 4: Reason Recorded (25 pts)
    reason_text = (james.get('suspend_reason') or "").lower()
    matches = [kw for kw in expected_reason_keywords if kw in reason_text]
    if len(matches) >= 1:
        score += 25
        feedback_parts.append(f"Reason matches keywords: {matches}")
    elif reason_text:
        score += 10 # Credit for entering A reason, even if wrong text
        feedback_parts.append(f"Reason recorded but keywords missing: '{reason_text}'")
    else:
        feedback_parts.append("No suspension reason recorded")

    # Criterion 5: Admin still active (Collateral check) (10 pts)
    if str(admin.get('approved_status', '')) == '1':
        score += 10
    else:
        feedback_parts.append("CRITICAL: Admin account was also suspended/altered!")

    # Pass Threshold: 65 (Needs status change + suspend state + collateral check)
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }