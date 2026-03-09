#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_agent_timeclock_entries(traj, env_info, task_info):
    """
    Verify that the timeclock entries were corrected to the specific target values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Target Values
    # Feb 24 Logout: 2026-02-24 17:30:00
    # Feb 25 Login:  2026-02-25 09:00:00
    target_feb24 = "2026-02-24 17:30:00"
    target_feb25 = "2026-02-25 09:00:00"
    admin_user = "6666"

    # Verify Feb 24 Record
    rec24 = result.get("feb24_logout")
    if rec24:
        # Check timestamp
        actual_24 = rec24.get("event_date")
        if actual_24 == target_feb24:
            score += 40
            feedback_parts.append("Feb 24 Logout corrected successfully (40/40)")
            
            # Check manager attribution (evidence of edit)
            mgr_24 = rec24.get("manager_user")
            if mgr_24 == admin_user:
                score += 10
                feedback_parts.append("Feb 24 Manager attribution verified (10/10)")
            else:
                feedback_parts.append(f"Feb 24 Manager attribution missing/wrong (Found: {mgr_24})")
        else:
            feedback_parts.append(f"Feb 24 Logout incorrect. Expected {target_feb24}, got {actual_24}")
    else:
        feedback_parts.append("Feb 24 Logout record not found")

    # Verify Feb 25 Record
    rec25 = result.get("feb25_login")
    if rec25:
        # Check timestamp
        actual_25 = rec25.get("event_date")
        if actual_25 == target_feb25:
            score += 40
            feedback_parts.append("Feb 25 Login corrected successfully (40/40)")
            
            # Check manager attribution
            mgr_25 = rec25.get("manager_user")
            if mgr_25 == admin_user:
                score += 10
                feedback_parts.append("Feb 25 Manager attribution verified (10/10)")
            else:
                feedback_parts.append(f"Feb 25 Manager attribution missing/wrong (Found: {mgr_25})")
        else:
            feedback_parts.append(f"Feb 25 Login incorrect. Expected {target_feb25}, got {actual_25}")
    else:
        feedback_parts.append("Feb 25 Login record not found")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }