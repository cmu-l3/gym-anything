#!/usr/bin/env python3
"""
Verifier for schedule_employee_activity task.
Verifies that a specific activity was scheduled in Odoo for 'Marc Demo'.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_employee_activity(traj, env_info, task_info):
    """
    Verify the scheduled activity using data exported from Odoo.
    
    Criteria:
    1. A new activity exists for Marc Demo (count increased).
    2. The activity was created during the task session (timestamp check).
    3. Activity Type is 'To-Do'.
    4. Summary contains 'Q4 Performance Review'.
    5. Due Date is '2025-12-15'.
    6. Note contains key phrases.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for script errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    max_score = 100
    feedback = []

    # Get metadata expectations
    meta = task_info.get("metadata", {})
    exp_summary = meta.get("expected_summary", "Q4 Performance Review")
    exp_date = meta.get("expected_date", "2025-12-15")
    exp_type = meta.get("expected_activity_type", "To-Do")
    exp_keywords = meta.get("expected_note_keywords", ["project", "goals"])

    # Extract actual data
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    details = result.get("activity_details", {})
    
    # 1. Activity Existence (30 pts)
    # Check if count increased OR if the latest activity is flagged as new
    created_during_task = details.get("created_during_task", False)
    
    if final_count > initial_count and created_during_task:
        score += 30
        feedback.append("New activity created successfully.")
    elif created_during_task:
        # Maybe count didn't change (one deleted, one added?) but we found a new one
        score += 30
        feedback.append("New activity created (count mismatch ignored).")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new activity was created during the task session."
        }

    # 2. Activity Type (15 pts)
    act_type = details.get("activity_type", "")
    if exp_type.lower() in act_type.lower():
        score += 15
        feedback.append(f"Correct activity type: {act_type}")
    else:
        feedback.append(f"Incorrect activity type: expected '{exp_type}', got '{act_type}'")

    # 3. Summary (20 pts)
    summary = details.get("summary", "")
    if exp_summary.lower() in summary.lower():
        score += 20
        feedback.append("Correct summary.")
    else:
        feedback.append(f"Incorrect summary: expected '{exp_summary}', got '{summary}'")

    # 4. Due Date (20 pts)
    date_deadline = details.get("date_deadline", "")
    if date_deadline == exp_date:
        score += 20
        feedback.append("Correct due date.")
    else:
        feedback.append(f"Incorrect due date: expected '{exp_date}', got '{date_deadline}'")

    # 5. Note Content (15 pts)
    note = details.get("note", "").lower()
    # Note in Odoo is HTML, so it might contain tags like <p>. Simple substring match is usually enough.
    found_keywords = [k for k in exp_keywords if k.lower() in note]
    if len(found_keywords) >= 1:
        score += 15
        feedback.append("Note content verified.")
    else:
        feedback.append("Note content missing required keywords.")

    passed = score >= 65  # Threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": details
    }