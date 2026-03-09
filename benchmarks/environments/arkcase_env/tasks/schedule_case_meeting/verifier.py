#!/usr/bin/env python3
"""
Verifier for schedule_case_meeting task.
"""

import json
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_case_meeting(traj, env_info, task_info):
    """
    Verifies that the agent scheduled the meeting correctly.
    
    Criteria:
    1. Event exists with correct title ("Oversight Review Board").
    2. Event date matches the requirement (5 days from start).
    3. Event time matches requirement (10:00 AM).
    4. Event description contains required text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    import tempfile
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

    # Check for script errors
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback = []
    
    # 1. Event Existence & Title (30 pts)
    found = result.get('found', False)
    event = result.get('event', {})
    
    if found:
        score += 30
        feedback.append("Event 'Oversight Review Board' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "No event found with title 'Oversight Review Board'."}

    # 2. Date Verification (30 pts)
    # API usually returns ISO dates like "2023-10-25T10:00:00.000Z" or milliseconds
    expected_date = result.get('expected_date')  # YYYY-MM-DD
    
    # Safely parse event start time
    event_start = event.get('start', '') or event.get('startDate', '') or event.get('dtstart', '')
    
    # Simple string match check for date part
    if expected_date and expected_date in str(event_start):
        score += 30
        feedback.append(f"Date matches {expected_date}.")
    else:
        feedback.append(f"Date mismatch. Expected {expected_date}, got {event_start}.")

    # 3. Time Verification (20 pts)
    # Expected: "10:00:00" or similar
    expected_time = result.get('expected_time', '10:00')
    # Check if '10:00' appears in the start string
    if '10:00' in str(event_start):
        score += 20
        feedback.append("Time matches 10:00.")
    else:
        feedback.append(f"Time mismatch. Got {event_start}.")

    # 4. Description Check (20 pts)
    description = event.get('description', '') or event.get('details', '')
    if "Mandatory review" in description:
        score += 20
        feedback.append("Description contains 'Mandatory review'.")
    else:
        feedback.append("Description missing or incorrect.")

    # Pass logic
    passed = score >= 80  # Requires correct event + correct date + (time OR description)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }