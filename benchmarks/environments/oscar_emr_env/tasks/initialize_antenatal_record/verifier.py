#!/usr/bin/env python3
"""
Verifier for initialize_antenatal_record task.
Verifies that the agent created an Antenatal Record 1 (AR1) with the correct LMP.
"""

import json
import os
import tempfile
from datetime import datetime, timedelta

def verify_antenatal_record(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    record_found = result.get('record_found', False)
    record_lmp = result.get('record_lmp', '')
    record_edd = result.get('record_edd', '')
    target_lmp = result.get('target_lmp', '')
    created_today = result.get('created_today', False)
    
    score = 0
    feedback = []

    # 3. Score - Record Existence (40 pts)
    if record_found:
        score += 40
        feedback.append("Antenatal Record 1 created.")
    else:
        return {"passed": False, "score": 0, "feedback": "No Antenatal Record 1 found for the patient."}

    # 4. Score - LMP Accuracy (30 pts)
    # Allow +/- 1 day tolerance for timezone/calculation differences
    lmp_correct = False
    if record_lmp and target_lmp:
        try:
            rec_date = datetime.strptime(record_lmp, "%Y-%m-%d")
            tgt_date = datetime.strptime(target_lmp, "%Y-%m-%d")
            delta = abs((rec_date - tgt_date).days)
            if delta <= 1:
                score += 30
                lmp_correct = True
                feedback.append(f"LMP recorded correctly: {record_lmp}.")
            else:
                feedback.append(f"LMP incorrect. Expected {target_lmp} (+/-1 day), found {record_lmp}.")
        except ValueError:
            feedback.append(f"Date format error in verification: {record_lmp} vs {target_lmp}.")
    else:
        feedback.append("LMP date missing in record.")

    # 5. Score - EDD Calculation (15 pts)
    # Check if EDD is not empty/null. We assume Oscar calculates it if LMP is entered.
    if record_edd and record_edd != "NULL" and record_edd != "0000-00-00":
        score += 15
        feedback.append(f"EDD calculated: {record_edd}.")
    else:
        feedback.append("EDD not calculated or missing.")

    # 6. Score - Anti-gaming / Timestamp (15 pts)
    if created_today:
        score += 15
        feedback.append("Record created during task window.")
    else:
        feedback.append("Record creation date does not match today (possible reuse of old data).")

    # 7. Final Assessment
    # Pass threshold: 70 points. Must have record + correct LMP.
    passed = (score >= 70) and record_found and lmp_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }