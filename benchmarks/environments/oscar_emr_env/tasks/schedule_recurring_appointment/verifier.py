#!/usr/bin/env python3
"""
Verifier for schedule_recurring_appointment task.
"""

import json
import logging
import os
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_recurring_appointment(traj, env_info, task_info):
    """
    Verify that a recurring appointment series was scheduled correctly.
    
    Criteria:
    1. At least one appointment exists for the patient (20 pts).
    2. Exactly 4 active appointments exist (30 pts).
    3. The first appointment is on the correct Start Date (Calculated "Next Tuesday") (15 pts).
    4. The start time is 10:00:00 for all appointments (15 pts).
    5. The appointments are on consecutive weeks (recurrence correct) (20 pts).
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
    target_start_date_str = result.get('target_start_date')
    
    score = 0
    feedback = []
    
    # Crit 1: Any appointments?
    if not appointments:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No appointments found for Michael Chang."
        }
    
    score += 20
    feedback.append("Appointments created.")
    
    # Crit 2: Correct Count (4)
    count = len(appointments)
    if count == 4:
        score += 30
        feedback.append("Correct number of sessions (4).")
    else:
        feedback.append(f"Incorrect number of sessions: found {count}, expected 4.")
        # partial credit if close? No, specific recurrence needed.
    
    # Sort by date just in case
    appointments.sort(key=lambda x: x['date'])
    
    # Crit 3: Start Date
    first_appt = appointments[0]
    first_date_str = first_appt.get('date')
    
    if first_date_str == target_start_date_str:
        score += 15
        feedback.append(f"Correct start date: {first_date_str}.")
    else:
        feedback.append(f"Wrong start date. Expected {target_start_date_str}, got {first_date_str}.")
        
    # Crit 4: Time (10:00:00)
    # Check all appointments
    all_times_correct = True
    for appt in appointments:
        # DB format usually HH:MM:00
        t = appt.get('start_time', '')
        if not t.startswith('10:00'):
            all_times_correct = False
            break
            
    if all_times_correct:
        score += 15
        feedback.append("Correct time (10:00) for all sessions.")
    else:
        feedback.append("One or more appointments have incorrect times.")

    # Crit 5: Consecutive Weeks (Recurrence)
    # Check intervals
    recurrence_correct = True
    if count > 1:
        try:
            fmt = '%Y-%m-%d'
            dates = [datetime.strptime(a['date'], fmt) for a in appointments]
            
            for i in range(len(dates) - 1):
                diff = (dates[i+1] - dates[i]).days
                if diff != 7:
                    recurrence_correct = False
                    feedback.append(f"Gap between appt {i+1} and {i+2} is {diff} days (expected 7).")
                    break
        except Exception as e:
            recurrence_correct = False
            feedback.append(f"Date parsing error: {e}")
    elif count == 1:
        recurrence_correct = False # Can't verify recurrence with 1 appt
        feedback.append("Cannot verify recurrence with only 1 appointment.")

    if recurrence_correct and count == 4:
        score += 20
        feedback.append("Recurrence pattern (weekly) is correct.")
    elif recurrence_correct and count > 1:
        # Partial credit if they did recurrence but wrong count
        score += 10
        feedback.append("Recurrence intervals are correct, but count is wrong.")

    passed = score >= 70 and count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }