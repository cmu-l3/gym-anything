#!/usr/bin/env python3
"""
Verifier for edit_patient_dob task.

Criteria:
1. Patient 'Mario Vega' exists (10 pts)
2. Date of Birth in DB is exactly '1980-03-15' (40 pts)
3. Date of Birth in API matches '1980-03-15' (20 pts)
4. Anti-gaming: Record was modified AFTER task start time (30 pts)
"""

import json
import os
import sys
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_patient_dob(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_dob = metadata.get('target_dob', '1980-03-15')

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
    feedback_parts = []
    
    # 1. Verify Patient Exists
    patient_uuid = result.get('patient_uuid')
    if patient_uuid:
        score += 10
        feedback_parts.append("Patient Mario Vega found")
    else:
        feedback_parts.append("Patient Mario Vega NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Verify DOB in Database
    final_dob_db = result.get('final_dob_db', '')
    # DB might return full datetime "1980-03-15 00:00:00" or just date
    if final_dob_db and final_dob_db.startswith(target_dob):
        score += 40
        feedback_parts.append(f"DB: DOB updated to {target_dob}")
    else:
        feedback_parts.append(f"DB: DOB incorrect (found '{final_dob_db}', expected '{target_dob}')")

    # 3. Verify DOB in API
    final_dob_api = result.get('final_dob_api', '')
    if final_dob_api and final_dob_api.startswith(target_dob):
        score += 20
        feedback_parts.append(f"API: DOB verified")
    else:
        feedback_parts.append(f"API: DOB mismatch")

    # 4. Anti-gaming: Timestamp check
    task_start = result.get('task_start_ts', 0)
    db_change_ts = result.get('db_date_changed_ts', 0)
    
    # Allow a small buffer for clock skew, but strictly change must look recent
    # If db_change_ts is 0, it means date_changed was NULL or parse failed
    if db_change_ts > task_start:
        score += 30
        feedback_parts.append("Modification verified during task")
    elif db_change_ts > 0:
        feedback_parts.append("Modification timestamp is OLD (pre-task?)")
    else:
        feedback_parts.append("No modification timestamp found")

    # Final Pass/Fail
    # Must have correct DOB in DB and decent score
    passed = (score >= 70) and final_dob_db.startswith(target_dob)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }