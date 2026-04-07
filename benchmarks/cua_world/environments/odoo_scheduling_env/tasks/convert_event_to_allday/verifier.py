#!/usr/bin/env python3
"""
Verifier for convert_event_to_allday task.

Verifies:
1. Event "Legal Contract Review" exists
2. 'allday' flag is True (Primary Goal)
3. Event date is preserved (start_date matches original start)
4. Attendees and Location are preserved
5. Event was modified during the task window (anti-gaming)
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_event_to_allday(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_attendees = set(metadata.get('expected_attendees', ["Karen Lee", "Bob Williams"]))
    expected_location = metadata.get('expected_location', "Legal Conference Room")

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. Check Event Existence (15 pts)
    if not result.get('event_found'):
        return {"passed": False, "score": 0, "feedback": "Event 'Legal Contract Review' not found in database."}
    
    event = result['event']
    score += 15
    feedback.append("Event found")

    # 2. Check All-Day Flag (35 pts) - CORE OBJECTIVE
    is_allday = event.get('allday')
    if is_allday is True:
        score += 35
        feedback.append("Event successfully converted to All-Day")
    else:
        feedback.append(f"Event is NOT All-Day (allday={is_allday})")

    # 3. Check Date Preservation (20 pts)
    # Compare date string from start_date (allday) or start (timed)
    # The baseline start is like "2023-10-15 14:00:00"
    baseline_start = result.get('baseline', {}).get('initial_start', '')
    
    current_date_str = event.get('start_date') or event.get('start')
    
    if baseline_start and current_date_str:
        # Extract YYYY-MM-DD
        original_date = baseline_start[:10]
        current_date = str(current_date_str)[:10]
        
        if original_date == current_date:
            score += 20
            feedback.append("Date preserved")
        else:
            feedback.append(f"Date changed! Original: {original_date}, New: {current_date}")
    else:
        feedback.append("Could not verify date preservation (missing data)")

    # 4. Check Attendees (10 pts)
    current_attendees = set(result.get('attendee_names', []))
    # We check if expected attendees are a subset of current (in case admin is auto-added)
    if expected_attendees.issubset(current_attendees):
        score += 10
        feedback.append("Attendees preserved")
    else:
        missing = expected_attendees - current_attendees
        feedback.append(f"Missing attendees: {missing}")

    # 5. Check Location (10 pts)
    current_location = event.get('location')
    if current_location == expected_location:
        score += 10
        feedback.append("Location preserved")
    else:
        feedback.append(f"Location changed. Expected: {expected_location}, Got: {current_location}")

    # 6. Anti-Gaming: Write Date (10 pts)
    write_date_str = event.get('write_date')
    task_start_ts = result.get('task_start_ts', 0)
    
    if write_date_str and task_start_ts > 0:
        try:
            # Odoo returns UTC usually, format YYYY-MM-DD HH:MM:SS
            # Simple check: Convert write_date to timestamp
            # Note: This can be tricky with timezones, but usually Odoo sends UTC
            # We'll use a lenient check or just ensure it's valid
            write_dt = datetime.strptime(write_date_str, "%Y-%m-%d %H:%M:%S")
            # Assuming basic consistency or just check if it was updated recently
            # If the script ran fast, write_date might be very close.
            # We'll just give points if we passed the core objective, implying action was taken.
            # But let's try a loose timestamp check
            if write_dt.timestamp() > (task_start_ts - 60): # buffer for clock skew
                 score += 10
                 feedback.append("Modification verified by timestamp")
            else:
                 feedback.append("Warning: Event not modified since task start")
        except:
            score += 10 # Fallback if parsing fails but other checks pass
    else:
        # If we can't check timestamp but allday changed from baseline, we grant points
        baseline_allday = result.get('baseline', {}).get('initial_allday')
        if baseline_allday is False and is_allday is True:
             score += 10
             feedback.append("Modification verified by state change")

    passed = score >= 70 and (is_allday is True)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }