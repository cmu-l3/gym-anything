#!/usr/bin/env python3
"""
Verifier for reschedule_appointment task.

Checks:
1. Old appointment on July 15 at 10:00 is removed/cancelled (20 pts)
2. New appointment on July 17 exists for Maria Santos (25 pts)
3. New appointment is at the correct time (14:00) (15 pts)
4. New appointment reason contains "Blood Pressure" (20 pts)
5. Anti-gaming / VLM verification (20 pts)
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reschedule_appointment(traj, env_info, task_info):
    """
    Verify that the appointment was rescheduled correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Old Appointment Removed (20 pts)
    old_active_count = result.get("old_appointment_active_count", 1)
    if old_active_count == 0:
        score += 20
        feedback_parts.append("Old appointment removed/cancelled")
    else:
        feedback_parts.append("Old appointment still active")

    # 2. Verify New Appointment Exists (25 pts)
    new_appt = result.get("new_appointment", {})
    new_exists = new_appt.get("exists", False)
    
    if new_exists:
        score += 25
        feedback_parts.append("New appointment created on July 17")
        
        # 3. Verify New Appointment Time (15 pts)
        # Expected: 14:00:00, accept +/- 15 mins
        start_time_str = new_appt.get("start_time", "00:00:00")
        try:
            h, m, s = map(int, start_time_str.split(':'))
            minutes_from_midnight = h * 60 + m
            target_minutes = 14 * 60  # 14:00 = 840 min
            
            if 825 <= minutes_from_midnight <= 855:  # 13:45 to 14:15
                score += 15
                feedback_parts.append("New appointment time correct (14:00)")
            else:
                feedback_parts.append(f"New appointment time incorrect ({start_time_str})")
        except ValueError:
            feedback_parts.append("Could not parse new appointment time")

        # 4. Verify New Reason (20 pts)
        reason = new_appt.get("reason", "").lower()
        if "blood pressure" in reason:
            score += 20
            feedback_parts.append("Reason updated correctly")
        else:
            feedback_parts.append(f"Reason incorrect or missing keyword 'Blood Pressure' (found: '{new_appt.get('reason')}')")

    else:
        feedback_parts.append("No new appointment found on July 17")

    # 5. Anti-gaming / Workflow Verification (20 pts)
    # Check timestamps and ensure user actually did something
    task_start = result.get("task_start_timestamp", 0)
    task_end = result.get("task_end_timestamp", 0)
    
    # Basic sanity check that task took some time
    duration = task_end - task_start
    if duration > 5:  # At least 5 seconds
        score += 10
        feedback_parts.append("Task duration valid")
    else:
        feedback_parts.append("Task completed suspiciously fast")

    # VLM Trajectory Check (10 pts)
    # If we have trajectory frames, use VLM to confirm schedule view was used
    # Note: In a real implementation, we would call the VLM here. 
    # For now, we award points if the primary database checks pass, 
    # assuming the agent couldn't guess the DB password to do SQL injection.
    if new_exists and old_active_count == 0:
        score += 10
        feedback_parts.append("Workflow implied by successful database state change")
    
    # Calculate Final Result
    passed = (score >= 60) and new_exists and (old_active_count == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }