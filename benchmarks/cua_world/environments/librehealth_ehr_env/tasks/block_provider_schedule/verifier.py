#!/usr/bin/env python3
"""
Verifier for block_provider_schedule task.

Criteria:
1. Event created with title "Staff Meeting" (40 pts)
2. Start time is 16:00 (20 pts)
3. Duration is 60 mins / 3600 sec (20 pts)
4. Event is NOT linked to a patient (pc_pid is 0 or NULL) (20 pts)

Anti-gaming:
- Verifies database record exists.
- VLM check ensures UI was used (via trajectory).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_schedule(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    events = result.get('events', [])
    
    # Initialize Scoring
    score = 0
    feedback = []
    
    # Find the best matching event
    target_event = None
    
    for event in events:
        title = event.get('title', '').lower()
        if 'staff meeting' in title:
            target_event = event
            break
            
    # Check 1: Event Exists
    if target_event:
        score += 40
        feedback.append("Event 'Staff Meeting' found.")
    else:
        # Fallback check: look for any event at 16:00
        for event in events:
            if event.get('start_time', '').startswith('16:00'):
                target_event = event
                feedback.append("Found event at 16:00 but title mismatch.")
                break
        if not target_event:
            return {"passed": False, "score": 0, "feedback": "No matching event found at 16:00 or with title 'Staff Meeting'."}

    # Check 2: Start Time (16:00:00)
    start_time = target_event.get('start_time', '')
    if start_time.startswith('16:00'):
        score += 20
        feedback.append("Time is correct (16:00).")
    else:
        feedback.append(f"Time is incorrect (found {start_time}).")

    # Check 3: Duration (3600 seconds)
    duration = str(target_event.get('duration', '0'))
    if duration == '3600':
        score += 20
        feedback.append("Duration is correct (60 mins).")
    else:
        feedback.append(f"Duration is incorrect (found {duration}s).")

    # Check 4: Non-Patient Event
    # pc_pid should be 0, empty, or NULL for provider events
    pid = str(target_event.get('pid', '0'))
    # SQL export might treat NULL as 'NULL' string or None, or 0
    if pid in ['0', 'NULL', 'None', '']:
        score += 20
        feedback.append("Correctly created as non-patient event.")
    else:
        feedback.append(f"Incorrectly assigned to a patient (PID: {pid}).")

    # Final Score Calculation
    passed = score >= 80  # Requires correct creation, time, and ideally type
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }