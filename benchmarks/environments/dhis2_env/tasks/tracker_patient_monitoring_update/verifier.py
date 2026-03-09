#!/usr/bin/env python3
"""
Verifier for tracker_patient_monitoring_update task.

Scoring (100 points total):
1. Patient Profile Updated (30 pts): Mobile number matches '077-123-456'
2. Note Added (20 pts): A note containing "planning travel" exists.
3. Event Scheduled (30 pts): A 'SCHEDULE' status event exists for Today + 7 days.
4. Search/Navigation (20 pts): Implicitly awarded if any of the above are modified on the correct TEI.

Pass Threshold: 60 points
"""

import json
import logging
import os
import shutil
import tempfile
from datetime import datetime, timedelta, date

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tracker_update(traj, env_info, task_info):
    """Verify that the patient record was updated correctly."""
    
    # 1. Setup Result Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_dir = tempfile.mkdtemp()
    local_result_path = os.path.join(temp_dir, "task_result.json")

    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)

    # 2. Extract Data
    phone_value = result.get("phone_value", "")
    note_found = result.get("note_found_text", False)
    events = result.get("events", [])
    
    score = 0
    feedback = []

    # 3. Verify Phone Number (30 pts)
    # Allow some flexibility in formatting (spaces, dashes)
    target_phone = "077-123-456"
    clean_phone_actual = ''.join(filter(str.isdigit, str(phone_value)))
    clean_phone_target = ''.join(filter(str.isdigit, target_phone))
    
    if clean_phone_actual == clean_phone_target:
        score += 30
        feedback.append("✅ Mobile number updated correctly.")
    elif phone_value:
        score += 10 # Partial credit for changing it to something else
        feedback.append(f"⚠️ Mobile number changed to '{phone_value}', expected '{target_phone}'.")
    else:
        feedback.append("❌ Mobile number not updated.")

    # 4. Verify Note (20 pts)
    if note_found:
        score += 20
        feedback.append("✅ Dashboard note added successfully.")
    else:
        feedback.append("❌ Note 'Patient planning travel' not found.")

    # 5. Verify Scheduled Event (30 pts)
    # Target date: Today + 7 days
    # We need to calculate what "Today" was in the environment. 
    # Ideally, we get this from the result file or assume verifier runs same day.
    # The setup script creates the enrollment using `date +%Y-%m-%d`.
    # Let's check for any scheduled event roughly 7 days from now.
    
    today = date.today()
    target_date = today + timedelta(days=7)
    target_date_str = target_date.strftime("%Y-%m-%d")
    
    event_scheduled = False
    event_date_found = ""
    
    for event in events:
        if event.get("status") == "SCHEDULE":
            due_date_str = event.get("dueDate", "").split('T')[0] # Handle ISO format if present
            
            # Allow +/- 1 day tolerance
            try:
                due_date = datetime.strptime(due_date_str, "%Y-%m-%d").date()
                diff = abs((due_date - target_date).days)
                if diff <= 1:
                    event_scheduled = True
                    event_date_found = due_date_str
                    break
            except ValueError:
                continue

    if event_scheduled:
        score += 30
        feedback.append(f"✅ Event successfully scheduled for {event_date_found}.")
    else:
        feedback.append(f"❌ No event scheduled for approx {target_date_str} (found: {[e.get('dueDate') for e in events if e.get('status')=='SCHEDULE']}).")

    # 6. Implicit Search Score (20 pts)
    # If they managed to update the phone OR add a note OR schedule an event, 
    # they must have found the patient.
    if score > 0:
        score += 20
        feedback.append("✅ Patient record accessed.")
    else:
        feedback.append("❌ Patient record was not modified.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }