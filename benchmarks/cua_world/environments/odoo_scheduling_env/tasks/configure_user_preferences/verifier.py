#!/usr/bin/env python3
"""
Verifier for configure_user_preferences task.

Checks if the Odoo admin user's preferences were correctly updated in the database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_user_preferences(traj, env_info, task_info):
    """
    Verify that the agent updated the user preferences correctly.
    
    Criteria:
    1. Timezone must be 'America/Chicago' (40 pts)
    2. Notification type must be 'email' (40 pts)
    3. State must have changed from baseline (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    target_tz = metadata.get('target_timezone', 'America/Chicago')
    target_notif = metadata.get('target_notification_type', 'email')
    
    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for errors in export
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    baseline = result.get('baseline', {})
    final = result.get('final', {})
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Check Timezone (40 pts)
    final_tz = final.get('tz')
    if final_tz == target_tz:
        score += 40
        feedback_parts.append(f"Timezone correctly set to {target_tz}")
    else:
        feedback_parts.append(f"Timezone incorrect (expected {target_tz}, got {final_tz})")

    # Criterion 2: Check Notification Type (40 pts)
    final_notif = final.get('notification_type')
    if final_notif == target_notif:
        score += 40
        feedback_parts.append(f"Notification type correctly set to {target_notif}")
    else:
        feedback_parts.append(f"Notification type incorrect (expected {target_notif}, got {final_notif})")
        
    # Criterion 3: Anti-gaming / Action verification (20 pts)
    # Check if the values are actually different from what we started with
    # (Setup script ensures start state != target state, so if we match target, we changed)
    changed_tz = final_tz != baseline.get('tz')
    changed_notif = final_notif != baseline.get('notification_type')
    
    if score >= 80:
        # If both are correct, we implicitly changed from baseline (guaranteed by setup_task.sh)
        score += 20
        feedback_parts.append("Configuration successfully updated from baseline")
    elif changed_tz or changed_notif:
        # Partial credit if they changed something but maybe got one wrong
        score += 20
        feedback_parts.append("Attempted changes detected")
    else:
        feedback_parts.append("No changes detected from baseline")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }