#!/usr/bin/env python3
"""
Verifier for schedule_recurring_series task.
Checks if 4 weekly appointments were created for the correct patient.
"""

import json
import os
import datetime
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_series(traj, env_info, task_info):
    """
    Verify scheduling of recurring appointments.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    appointments = result.get('appointments', [])
    metadata = task_info.get('metadata', {})
    
    expected_dates = ["2026-04-06", "2026-04-13", "2026-04-20", "2026-04-27"]
    expected_time_prefix = "09:00" # Match HH:MM
    expected_keywords = metadata.get('reason_keywords', ["smoking", "cessation"])

    score = 0
    feedback_parts = []
    
    # Analyze Appointments
    found_dates = []
    valid_appts = 0
    reason_matches = 0
    time_matches = 0
    
    for appt in appointments:
        appt_date = appt.get('date', '')
        appt_time = appt.get('time', '')
        appt_reason = appt.get('reason', '').lower()
        
        # Check if this appointment is on one of the expected dates
        if appt_date in expected_dates:
            if appt_date not in found_dates:
                found_dates.append(appt_date)
                valid_appts += 1
                
                # Check Time
                if appt_time.startswith(expected_time_prefix):
                    time_matches += 1
                
                # Check Reason
                if any(kw in appt_reason for kw in expected_keywords):
                    reason_matches += 1

    # Scoring
    # 1. Series Completeness (25 pts): 4 appts
    # 2. First Appointment (25 pts): Apr 6 exists
    # 3. Weekly Interval (20 pts): All 4 exist (implied by dates check)
    # 4. Reason Text (15 pts)
    # 5. Time Consistency (15 pts)

    # 1 & 3 combined: Count correct dates
    if len(found_dates) == 4:
        score += 45 # 25 + 20
        feedback_parts.append("All 4 appointments found on correct dates.")
    elif len(found_dates) >= 1:
        score += (len(found_dates) * 10)
        feedback_parts.append(f"Found {len(found_dates)}/4 appointments.")
    else:
        feedback_parts.append("No appointments found on target dates.")

    # 2. First Appointment
    if "2026-04-06" in found_dates:
        score += 25
        feedback_parts.append("Start date verified.")
    else:
        feedback_parts.append("Start date (Apr 6) missing.")

    # 4. Reason Text (scaled by how many were correct)
    if valid_appts > 0:
        reason_score = (reason_matches / valid_appts) * 15
        score += reason_score
        if reason_matches < valid_appts:
             feedback_parts.append(f"Reason incorrect on {valid_appts - reason_matches} appts.")
        else:
             feedback_parts.append("Reason correct.")

    # 5. Time Consistency
    if valid_appts > 0:
        time_score = (time_matches / valid_appts) * 15
        score += time_score
        if time_matches < valid_appts:
             feedback_parts.append(f"Time incorrect on {valid_appts - time_matches} appts.")
        else:
             feedback_parts.append("Time correct.")

    passed = score >= 75 and len(found_dates) >= 3

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback_parts)
    }