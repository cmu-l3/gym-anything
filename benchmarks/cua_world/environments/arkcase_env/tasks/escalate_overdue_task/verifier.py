#!/usr/bin/env python3
"""
Verifier for 'escalate_overdue_task'.

Checks:
1. Priority upgraded to High.
2. Due Date extended to at least tomorrow.
3. Assignee changed to admin.
4. Changes persisted to backend.
"""

import json
import os
import tempfile
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_escalate_overdue_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    # --- Check 1: Data Retrieval ---
    if not result.get('task_found'):
        return {"passed": False, "score": 0, "feedback": "Target task could not be retrieved from system (deleted or never created)."}
    
    task_data = result.get('api_data', {})
    meta = result.get('meta', {})
    
    # --- Check 2: Priority (30 pts) ---
    # ArkCase priority might be stored as "High" or numeric. 
    # Usually strings in API: "High", "Medium", "Low".
    priority = str(task_data.get('priority', '')).lower()
    if priority == 'high' or priority == 'critical':
        score += 30
        feedback.append("Priority correctly set to High.")
    else:
        feedback.append(f"Priority incorrect. Expected 'High', got '{task_data.get('priority')}'")

    # --- Check 3: Assignee (30 pts) ---
    # Assignee might be an object or string.
    assignee = task_data.get('assignee', '')
    # Handle case where assignee is a dict
    if isinstance(assignee, dict):
        assignee_name = assignee.get('username', assignee.get('name', ''))
    else:
        assignee_name = str(assignee)
    
    if 'arkcase-admin' in assignee_name or 'arkcase-admin' in str(task_data):
        score += 30
        feedback.append("Assignee correctly updated to arkcase-admin.")
    else:
        feedback.append(f"Assignee incorrect. Expected 'arkcase-admin', got '{assignee_name}'")

    # --- Check 4: Due Date (20 pts) ---
    due_date_str = task_data.get('dueDate', '')
    ref_tomorrow = meta.get('ref_date_tomorrow')
    
    date_passed = False
    if due_date_str:
        try:
            # Parse ISO date (e.g., 2023-10-25T17:00:00.000Z)
            # Simplification: Compare YYYY-MM-DD
            due_date_val = due_date_str.split('T')[0]
            if due_date_val >= ref_tomorrow:
                score += 20
                date_passed = True
                feedback.append(f"Due date extended to {due_date_val}.")
            else:
                feedback.append(f"Due date {due_date_val} is not in the future (Target >= {ref_tomorrow}).")
        except:
            feedback.append(f"Could not parse due date: {due_date_str}")
    else:
        feedback.append("No due date found on task.")

    # --- Check 5: Modification (20 pts) ---
    # Ensure change happened during task
    last_mod = task_data.get('lastModifiedDate', '') or task_data.get('modifiedDate', '')
    # If API doesn't return mod date, checking specific values is usually enough proof of work
    # assuming initial state was different.
    # Initial state: Medium, generic-user, Yesterday.
    # If Priority changed AND Assignee changed, work was definitely done.
    
    work_verified = (priority == 'high' or priority == 'critical') and ('arkcase-admin' in assignee_name)
    if work_verified:
        score += 20
        feedback.append("Task modifications verified.")
    elif score > 0:
        score += 10 # Partial credit for attempted modification
        feedback.append("Partial modifications detected.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }