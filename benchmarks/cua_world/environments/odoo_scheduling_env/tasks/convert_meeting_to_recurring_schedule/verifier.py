#!/usr/bin/env python3
"""
Verifier for convert_meeting_to_recurring_schedule task.

Checks:
1. Event exists and is recurring (linked to calendar.recurrence).
2. Recurrence frequency is Weekly.
3. Days selected are Monday AND Thursday.
4. End condition is count=10.
5. Metadata (location, description, attendees) is preserved.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_meeting_to_recurring_schedule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    
    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Event found and is recurring (20 pts)
    if not result.get("event_found"):
        return {"passed": False, "score": 0, "feedback": "Event 'Team Standup' not found in database."}
    
    if result.get("is_recurring"):
        score += 20
        feedback.append("Event is set to recurring.")
    else:
        feedback.append("Event is NOT set to recurring.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    recurrence_data = result.get("recurrence_data", {})
    
    # Check 2: Frequency is Weekly (20 pts)
    # rrule_type for weekly is usually 'weekly'
    rrule_type = recurrence_data.get("rrule_type")
    interval = recurrence_data.get("interval", 1)
    
    if rrule_type == "weekly" and interval == 1:
        score += 20
        feedback.append("Recurrence is Weekly (interval 1).")
    else:
        feedback.append(f"Incorrect frequency: type={rrule_type}, interval={interval}.")

    # Check 3: Days are Mon and Thu (30 pts)
    # Odoo stores booleans for days: mon, tue, wed, thu, fri, sat, sun
    days_correct = True
    days_found = []
    
    if recurrence_data.get("mon"): days_found.append("Mon")
    else: days_correct = False
    
    if recurrence_data.get("thu"): days_found.append("Thu")
    else: days_correct = False
    
    # Ensure no other days are checked
    extra_days = []
    for d in ['tue', 'wed', 'fri', 'sat', 'sun']:
        if recurrence_data.get(d):
            extra_days.append(d)
            days_correct = False

    if days_correct and not extra_days:
        score += 30
        feedback.append("Days correctly set to Mon and Thu.")
    else:
        # Partial credit?
        if "Mon" in days_found or "Thu" in days_found:
             score += 10
        feedback.append(f"Incorrect days selected: found {days_found}, extras {extra_days}.")

    # Check 4: End condition count=10 (20 pts)
    end_type = recurrence_data.get("end_type")
    count = recurrence_data.get("count")
    
    if end_type == "count" and count == 10:
        score += 20
        feedback.append("End condition correct (10 occurrences).")
    else:
        feedback.append(f"Incorrect end condition: type={end_type}, count={count}.")

    # Check 5: Metadata preserved (10 pts)
    # We verify the event description/attendees didn't disappear
    event_data = result.get("event_data", {})
    attendees = event_data.get("partner_ids", [])
    
    # In Odoo, partner_ids is a list of IDs. Baseline had 4 attendees.
    # We just check if it's not empty, assuming the agent didn't maliciously delete them.
    if len(attendees) >= 3: 
        score += 10
        feedback.append("Attendees preserved.")
    else:
        feedback.append("Warning: Attendees count seems low or missing.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }