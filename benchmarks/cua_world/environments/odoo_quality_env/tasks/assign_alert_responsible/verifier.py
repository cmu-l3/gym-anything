#!/usr/bin/env python3
"""
Verifier for assign_alert_responsible task in Odoo.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_alert_responsible(traj, env_info, task_info):
    """
    Verify that the agent assigned the Administrator to the specific quality alert.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    max_score = 100
    feedback_parts = []
    
    # Check 1: Alert exists (10 pts)
    if result.get("alert_found"):
        score += 10
        feedback_parts.append("Target quality alert found.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target quality alert 'Coating Peeling - Large Cabinet' not found."
        }

    # Data extraction
    alert_data = result.get("alert_data", {})
    user_id_field = alert_data.get("user_id") # Odoo returns many2one as [id, "Name"] or False

    # Check 2: User is assigned (30 pts)
    if user_id_field:
        score += 30
        feedback_parts.append("Responsible user field is set.")
    else:
        feedback_parts.append("Responsible user field is empty.")

    # Check 3: User is correct (40 pts)
    # user_id_field is typically [2, "Administrator"]
    actual_uid = user_id_field[0] if isinstance(user_id_field, list) else user_id_field
    expected_uid = task_info.get("metadata", {}).get("expected_user_id", 2)
    
    if actual_uid == expected_uid:
        score += 40
        feedback_parts.append("Correct user (Administrator) assigned.")
    elif user_id_field:
        score += 10 # Partial credit for assigning *someone* else
        feedback_parts.append(f"Wrong user assigned (ID: {actual_uid}).")

    # Check 4: Anti-gaming - Alert count check (20 pts)
    # Ensure they didn't just create a NEW alert instead of editing the existing one
    current_count = result.get("current_alert_count", 0)
    baseline_count = result.get("baseline_alert_count", 0)
    
    if baseline_count != -1:
        if current_count == baseline_count:
            score += 20
            feedback_parts.append("Alert count valid (no duplicate created).")
        elif current_count > baseline_count:
            feedback_parts.append("New alerts detected (possible duplication).")
            # Penalize slightly but don't fail if they did the job
            score += 5 
    else:
        # Fallback if baseline missing
        score += 20

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }