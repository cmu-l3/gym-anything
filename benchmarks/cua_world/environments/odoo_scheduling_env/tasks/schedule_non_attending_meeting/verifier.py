#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_non_attending_meeting(traj, env_info, task_info):
    """
    Verify the meeting was scheduled correctly and the agent removed themselves.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Init Scoring
    score = 0
    feedback = []
    
    # 1. Event Existence (10 pts)
    if not result.get("event_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Event 'Executive Severance Review' not found in calendar."
        }
    score += 10
    feedback.append("Event created.")

    event = result.get("event_details", {})
    
    # 2. Date and Time Check (15 pts)
    # Target: Thursday of next week at 14:00
    # We calculate the expected date string dynamically to match environment logic
    try:
        now = datetime.now()
        # Logic matching setup_data.py / setup_task.sh
        days_to_monday = (7 - now.weekday()) % 7 or 7
        next_monday = now + timedelta(days=days_to_monday)
        target_thursday = next_monday + timedelta(days=3)
        target_date_str = target_thursday.strftime('%Y-%m-%d')
        
        # Odoo start time string format: '2023-10-25 14:00:00'
        # Note: Odoo stores DB times in UTC. 
        # The env is likely running in UTC or the python script output raw DB value.
        # If the agent scheduled for 2:00 PM (14:00) in the UI, and the timezone is UTC,
        # it should be 14:00 in DB.
        
        event_start = event.get("start", "")
        if target_date_str in event_start and "14:00" in event_start:
            score += 15
            feedback.append("Date and time correct (Thursday 14:00).")
        else:
            feedback.append(f"Date/Time incorrect. Expected {target_date_str} 14:00, got {event_start}")
    except Exception as e:
        feedback.append(f"Error validating date: {e}")

    # 3. Location Check (10 pts)
    loc = event.get("location", "") or ""
    if "HR Private Office" in loc:
        score += 10
        feedback.append("Location correct.")
    else:
        feedback.append(f"Location incorrect. Expected 'HR Private Office', got '{loc}'")

    # 4. Attendees Check (25 pts)
    attendee_names = result.get("attendee_names", [])
    # Normalize for case insensitive check
    attendee_names_lower = [n.lower() for n in attendee_names]
    
    has_grace = any("grace patel" in n for n in attendee_names_lower)
    has_frank = any("frank rivera" in n for n in attendee_names_lower)
    
    if has_grace and has_frank:
        score += 25
        feedback.append("Required attendees (Grace & Frank) present.")
    else:
        feedback.append(f"Missing required attendees. Found: {attendee_names}")

    # 5. Self-Removal Check (40 pts) - CRITICAL
    admin_present = result.get("admin_is_attendee", True)
    
    if not admin_present:
        score += 40
        feedback.append("Administrator successfully removed from attendees.")
    else:
        feedback.append("FAILED: Administrator is still listed as an attendee.")

    # Pass Threshold
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }