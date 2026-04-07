#!/usr/bin/env python3
"""
Verifier for schedule_monthly_floating_meeting task.

Verifies:
1. Event "Department All-Hands" exists.
2. Start time is 14:00 (2 PM).
3. Recurrence is configured as Monthly.
4. Recurrence uses "Day of week" logic (First Monday) NOT "Day of month" logic.
"""

import json
import os
import tempfile
import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_monthly_floating_meeting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    passed = False
    
    # 2. Analyze Results
    event_found = result.get("event_found", False)
    event_details = result.get("event_details", {})
    recurrence_found = result.get("recurrence_found", False)
    rec_details = result.get("recurrence_details", {})

    # CRITERION 1: Event Created (10 pts)
    if event_found:
        score += 10
        feedback.append("Event 'Department All-Hands' created.")
    else:
        feedback.append("Event 'Department All-Hands' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # CRITERION 2: Correct Start Time (14:00) (10 pts)
    # Odoo stores time in UTC in database usually, but XML-RPC read might return string.
    # The setup script reads the raw string.
    # Note: Odoo standardizes on UTC in backend. If user sets 14:00 local (assuming browser timezone matches container timezone),
    # we need to be careful. However, usually 'start' field in Odoo RPC is UTC.
    # Container timezone is UTC? The setup script sets TZ?
    # Let's assume the agent sets it to 14:00 in the UI.
    # If the environment is UTC, then DB is UTC 14:00.
    start_str = event_details.get("start", "")
    try:
        if start_str:
            # format: YYYY-MM-DD HH:MM:SS
            time_part = start_str.split(" ")[1]
            hour = int(time_part.split(":")[0])
            minute = int(time_part.split(":")[1])
            
            # Allow tight tolerance on minute, exact on hour (assuming 14:00 set in UI results in 14:00 stored if UTC)
            # If the user sets 2:00 PM, we expect 14:00.
            if hour == 14 and 0 <= minute <= 5:
                score += 10
                feedback.append("Start time correct (14:00).")
            else:
                feedback.append(f"Start time incorrect (Found {hour}:{minute:02d}, Expected 14:00).")
    except Exception as e:
        feedback.append(f"Could not parse start time: {e}")

    # CRITERION 3: Recurrence exists and is Monthly (20 pts)
    if recurrence_found:
        rrule_type = rec_details.get("rrule_type", "")
        if rrule_type == "monthly":
            score += 20
            feedback.append("Recurrence frequency is Monthly.")
        else:
            feedback.append(f"Recurrence frequency incorrect (Found {rrule_type}, Expected monthly).")
    else:
        feedback.append("No recurrence rule configured.")

    # CRITERION 4: Recurrence is 'Floating' (First Monday) NOT 'Fixed Date' (40 pts)
    # Correct configuration: month_by='day', byday='1', weekday='MO'
    # Incorrect configuration: month_by='date'
    if recurrence_found:
        month_by = rec_details.get("month_by")
        byday = rec_details.get("byday")
        weekday = rec_details.get("weekday")
        
        if month_by == "day":
            score += 20
            feedback.append("Recurrence set to 'By Day' (Floating) correctly.")
            
            if str(byday) == "1" and str(weekday).upper() == "MO":
                score += 20
                feedback.append("Recurrence pattern 'First Monday' correct.")
            else:
                feedback.append(f"Recurrence pattern incorrect (Found {byday} {weekday}, Expected 1st MO).")
        elif month_by == "date":
            feedback.append("Recurrence is set to 'By Date' (e.g., the 5th) instead of 'First Monday'.")
        else:
            feedback.append(f"Recurrence type unknown ({month_by}).")

    # CRITERION 5: Start Date is correct (First Monday of next month) (20 pts)
    # We calculate the expected date in python and compare
    try:
        if start_str:
            start_date_str = start_str.split(" ")[0] # YYYY-MM-DD
            start_date = datetime.datetime.strptime(start_date_str, "%Y-%m-%d").date()
            
            # Calculate next month's first Monday relative to today
            today = datetime.date.today()
            # Logic: Go to 1st of next month, then find first Monday
            if today.month == 12:
                next_month = today.replace(year=today.year+1, month=1, day=1)
            else:
                next_month = today.replace(month=today.month+1, day=1)
            
            # Find first monday of next_month
            # weekday(): Mon=0, Sun=6
            days_wait = (0 - next_month.weekday()) % 7
            expected_date = next_month + datetime.timedelta(days=days_wait)
            
            if start_date == expected_date:
                score += 20
                feedback.append(f"Start date correct ({start_date}).")
            else:
                # Be lenient if they picked the *current* month's first monday if today is before it? 
                # Task says "upcoming month".
                feedback.append(f"Start date incorrect (Found {start_date}, Expected {expected_date}).")
    except Exception as e:
        pass

    # Success determination
    # Need at least 70 points
    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }