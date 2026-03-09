#!/usr/bin/env python3
"""
Verifier for inactivate_patient task.
Verifies that the patient status was changed to 'IN' (Inactive) in the database.
"""

import json
import logging
import os
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inactivate_patient(traj, env_info, task_info):
    """
    Verify patient inactivation.
    
    Criteria:
    1. Patient record exists (integrity check).
    2. Patient status is 'IN' (Inactive).
    3. Record was updated AFTER task start time (anti-gaming).
    4. Patient name/DOB remains unchanged (integrity check).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('patient_fname', 'Maria')
    expected_lname = metadata.get('patient_lname', 'Santos')
    expected_dob = metadata.get('patient_dob', '1978-06-22')
    
    score = 0
    feedback_parts = []
    
    # 1. Check if patient was found (10 pts)
    if not result.get('patient_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Patient record 'Maria Santos' not found in database. Was it deleted?"
        }
    score += 10
    feedback_parts.append("Patient record found")

    # 2. Check Status (40 pts)
    final_status = result.get('final_status', '')
    if final_status == 'IN':
        score += 40
        feedback_parts.append("Status correctly set to Inactive (IN)")
    elif final_status == 'AC':
        feedback_parts.append("Status is still Active (AC) - No change detected")
    else:
        feedback_parts.append(f"Status is set to '{final_status}' (Expected: IN)")

    # 3. Anti-Gaming: Check Timestamp (30 pts)
    task_start = result.get('task_start_time', 0)
    last_update = result.get('last_update_timestamp', 0)
    
    # Oscar stores dates, sometimes times depending on version/config. 
    # If the setup script sets lastUpdateDate to yesterday, and now it's > start, it was modified.
    if last_update >= task_start:
        score += 30
        feedback_parts.append("Record modified during task window")
    else:
        feedback_parts.append("Record NOT modified during task (timestamp unchanged)")
        # If status is correct but timestamp isn't, they might have done nothing if it was already IN (setup should prevent this)
        # Or setup script failed to reset date.
        
    # 4. Integrity Check (20 pts)
    # Ensure they didn't overwrite the name or details while trying to update status
    result_name = result.get('integrity_name', '')
    result_dob = result.get('integrity_dob', '')
    expected_name = f"{expected_fname} {expected_lname}"
    
    if result_name == expected_name and result_dob == expected_dob:
        score += 20
        feedback_parts.append("Patient demographics preserved")
    else:
        feedback_parts.append(f"Demographics altered! Found: {result_name} {result_dob}")

    passed = (score >= 90) # Requires correct status + timestamp + integrity + found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }