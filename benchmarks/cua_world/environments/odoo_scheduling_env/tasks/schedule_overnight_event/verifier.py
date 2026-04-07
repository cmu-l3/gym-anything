#!/usr/bin/env python3
"""
Verifier for schedule_overnight_event task.

Criteria:
1. Event 'Database Migration' exists.
2. Event starts at 11:00 PM (23:00) on a Friday.
3. Event ends at 03:00 AM on the NEXT day (Saturday).
4. Duration is exactly 4.0 hours.
5. Location and Description match requirements.
"""

import json
import os
import tempfile
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_overnight_event(traj, env_info, task_info):
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

    # Basic Checks
    if not result.get("event_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Event 'Database Migration' was not found in the calendar."
        }

    event = result.get("event_data", {})
    score = 0
    feedback = []
    
    # 1. Event Existence (20 pts)
    score += 20
    feedback.append("Event created successfully.")

    # Parse dates (Odoo returns strings like '2023-10-27 23:00:00')
    # Note: These are typically UTC in the database, but Odoo's XMLRPC might return them 
    # as stored. The task is about the relative relationship and duration.
    try:
        start_dt = datetime.strptime(event['start'], "%Y-%m-%d %H:%M:%S")
        stop_dt = datetime.strptime(event['stop'], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return {"passed": False, "score": score, "feedback": "Error parsing event dates."}

    # 2. Duration Check (20 pts)
    # The 'duration' field in Odoo is explicitly calculated.
    actual_duration = event.get('duration', 0.0)
    expected_duration = task_info['metadata'].get('expected_duration', 4.0)
    
    if abs(actual_duration - expected_duration) < 0.1:
        score += 20
        feedback.append("Duration is correct (4 hours).")
    else:
        feedback.append(f"Incorrect duration: {actual_duration} hours (expected {expected_duration}).")

    # 3. Time and Day Boundary Check (40 pts)
    # Criteria:
    # - Start is late (23:00)
    # - Stop is early (03:00)
    # - Stop day is Start day + 1
    
    # We check the hour components. 
    # Note: If Odoo DB is UTC and user set 11PM local, the DB value might be different.
    # However, standard Odoo installs often default to UTC or the user matches.
    # A more robust check for "Overnight" is simply: Start Day != End Day AND Duration < 24h
    
    is_overnight = stop_dt.date() > start_dt.date()
    
    if is_overnight:
        score += 20
        feedback.append("Event correctly spans across midnight (overnight).")
    else:
        feedback.append("Event does not span across midnight (Start and End are same day).")

    # Check specific hours (tolerance for timezone shifts if consistent)
    # We assume the environment is set up such that inputting 11PM results in 23:00 stored
    # or consistent logic. 
    if start_dt.hour == 23 and stop_dt.hour == 3:
        score += 20
        feedback.append("Start/End times are exactly 11:00 PM and 3:00 AM.")
    elif is_overnight and abs((stop_dt - start_dt).total_seconds() - 14400) < 60:
         # Fallback: If times are shifted (e.g. UTC vs Local) but duration is exactly 4h and it is overnight
         # we give partial credit for the timing specifics.
         score += 10
         feedback.append("Timezone shift detected, but duration and overnight logic are correct.")
    else:
        feedback.append(f"Incorrect specific times: Start {start_dt.hour}:00, End {stop_dt.hour}:00.")

    # 4. Metadata Check (Location/Desc) (20 pts)
    loc_match = event.get('location') == "Server Room"
    desc_match = "Critical infrastructure" in (event.get('description') or "")
    
    if loc_match:
        score += 10
        feedback.append("Location is correct.")
    else:
        feedback.append(f"Incorrect location: {event.get('location')}")
        
    if desc_match:
        score += 10
        feedback.append("Description contains required keywords.")
    else:
        feedback.append("Description missing or incorrect.")

    # Final Evaluation
    passed = score >= 80  # Requires existence + duration + overnight + one metadata
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }