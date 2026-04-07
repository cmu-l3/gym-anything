#!/usr/bin/env python3
"""
Verifier for correct_encounter_datetime task.

Criteria:
1. Encounter Date is 2025-01-15 (40 pts)
2. Encounter Time is 14:00 +/- 5 mins (30 pts)
3. Encounter was actually modified (date_changed > task_start) (20 pts)
4. Encounter is not voided (10 pts)
"""

import json
import os
import sys
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_encounter_datetime(traj, env_info, task_info):
    """
    Verify that the agent corrected the encounter timestamp.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Values
    final_datetime_str = result.get("final_encounter_datetime", "").strip() # Format: YYYY-MM-DD HH:MM:SS
    date_changed_str = result.get("date_changed_db", "").strip()
    is_voided = str(result.get("is_voided", "1")).strip()
    task_start_ts = result.get("task_start_timestamp", 0)

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion: Not Voided (10 pts)
    if is_voided == "0":
        score += 10
        feedback.append("Encounter is active (not voided).")
    else:
        feedback.append("Encounter was voided/deleted.")
        return {"passed": False, "score": 0, "feedback": "Encounter was deleted instead of corrected."}

    # Criterion: Modification Proof (20 pts)
    # Check if date_changed is after task start
    modified_during_task = False
    if date_changed_str and date_changed_str.lower() != "null":
        try:
            # DB format usually YYYY-MM-DD HH:MM:SS
            changed_dt = datetime.strptime(date_changed_str, "%Y-%m-%d %H:%M:%S")
            changed_ts = changed_dt.timestamp()
            if changed_ts > task_start_ts:
                score += 20
                modified_during_task = True
                feedback.append("Encounter was modified during the task.")
            else:
                feedback.append(f"Encounter last modified before task ({date_changed_str}).")
        except ValueError:
            feedback.append("Could not parse modification timestamp.")
    else:
        feedback.append("Encounter was not modified (no date_changed).")

    # Criterion: Date and Time Check (70 pts total)
    target_dt_str = "2025-01-15 14:00:00"
    target_dt = datetime.strptime(target_dt_str, "%Y-%m-%d %H:%M:%S")
    
    dt_correct = False
    
    if final_datetime_str and final_datetime_str.lower() != "null":
        try:
            final_dt = datetime.strptime(final_datetime_str, "%Y-%m-%d %H:%M:%S")
            
            # Check Date (40 pts)
            if final_dt.date() == target_dt.date():
                score += 40
                feedback.append("Date is correct (2025-01-15).")
                
                # Check Time (30 pts)
                # Allow +/- 5 minutes tolerance
                diff_seconds = abs((final_dt - target_dt).total_seconds())
                if diff_seconds <= 300: # 5 minutes
                    score += 30
                    feedback.append(f"Time is correct ({final_dt.strftime('%H:%M')}).")
                    dt_correct = True
                else:
                    feedback.append(f"Time is incorrect. Expected ~14:00, got {final_dt.strftime('%H:%M')}.")
            else:
                feedback.append(f"Date is incorrect. Expected 2025-01-15, got {final_dt.date()}.")
                
        except ValueError:
            feedback.append(f"Could not parse final datetime: {final_datetime_str}")
    else:
        feedback.append("No encounter datetime found.")

    # 4. Final Verdict
    # Must have modified the record AND got the date correct to pass
    passed = (score >= 70) and modified_during_task and dt_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }