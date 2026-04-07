#!/usr/bin/env python3
"""
Verifier for transition_program_state task.

Criteria:
1. Patient 'Olen Bayer' has a state 'On ART' in 'HIV Care and Treatment'.
2. The 'On ART' state started TODAY (matches task date).
3. The 'On ART' state record was created during the task (anti-gaming).
4. The program enrollment is NOT completed (date_completed is null).
5. The previous state 'Pre-ART' has an end date equal to today (transition occurred).
"""

import json
import os
import sys
import tempfile
from datetime import datetime, date

def verify_transition_program_state(traj, env_info, task_info):
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

    states = result.get("patient_states", [])
    task_start = result.get("task_start", 0)
    today_str = date.today().strftime("%Y-%m-%d")

    score = 0
    feedback_parts = []
    
    # 1. Check for "On ART" state
    on_art_state = None
    pre_art_state = None
    
    for s in states:
        s_name = s.get("state", "")
        if "On ART" in s_name:
            on_art_state = s
        elif "Pre-ART" in s_name:
            pre_art_state = s

    # Criterion 1: Target state exists (40 pts)
    if on_art_state:
        score += 40
        feedback_parts.append("'On ART' state found.")
    else:
        feedback_parts.append("'On ART' state NOT found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # Criterion 2: Target state start date is Today (20 pts)
    start_date = on_art_state.get("start_date", "").split(" ")[0] # Handle datetime string
    if start_date == today_str:
        score += 20
        feedback_parts.append("State start date is correct (Today).")
    else:
        feedback_parts.append(f"State start date incorrect. Expected {today_str}, got {start_date}.")

    # Criterion 3: Enrollment is Active (Not Completed) (20 pts)
    # If enrollment_completed is present/not-null, user ended the program instead of transitioning
    completed_date = on_art_state.get("enrollment_completed")
    if not completed_date:
        score += 20
        feedback_parts.append("Program enrollment is correctly active (not completed).")
    else:
        feedback_parts.append("FAIL: Program enrollment was completed/ended. Goal was to transition state only.")

    # Criterion 4: Previous state 'Pre-ART' ended today (20 pts)
    if pre_art_state:
        end_date = pre_art_state.get("end_date")
        if end_date:
            end_date_str = end_date.split(" ")[0]
            if end_date_str == today_str:
                score += 20
                feedback_parts.append("Previous state 'Pre-ART' correctly ended today.")
            else:
                feedback_parts.append(f"Previous state ended on {end_date_str}, expected {today_str}.")
        else:
            feedback_parts.append("Previous state 'Pre-ART' was not ended (transition incomplete).")
    else:
        feedback_parts.append("Previous state record missing (setup issue or deleted).")

    # Anti-gaming: Check creation timestamp
    created_str = on_art_state.get("state_date_created", "")
    if created_str:
        try:
            # Parse SQL timestamp "YYYY-MM-DD HH:MM:SS"
            created_dt = datetime.strptime(created_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
            if created_dt.timestamp() > float(task_start):
                feedback_parts.append("Data verification: Record created during task.")
            else:
                score = 0
                feedback_parts.append("ANTI-GAMING FAIL: Record created before task started.")
        except ValueError:
            pass # Ignore timestamp parsing errors if format differs

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }