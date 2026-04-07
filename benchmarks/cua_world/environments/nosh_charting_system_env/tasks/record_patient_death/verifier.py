#!/usr/bin/env python3
"""
Verifier for record_patient_death task.
Checks if the patient's record in the database was updated with the correct date of death.
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_patient_death(traj, env_info, task_info):
    """
    Verify that the patient Albert Zweig was marked as deceased with date 2025-11-30.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_dod = metadata.get('date_of_death', '2025-11-30')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_dump = result.get('db_record_dump', '')
    target_pid = result.get('target_pid')

    if not target_pid or not db_dump:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target patient not found in database or database query failed."
        }

    score = 0
    feedback_parts = []

    # Criterion 1: Patient Identification (20 pts)
    # The fact that we have a db_dump for the specific PID implies the patient exists.
    score += 20
    feedback_parts.append("Patient record located")

    # Criterion 2: Date of Death Accuracy (50 pts)
    # Search for the date string in the dump. This handles variable column names 
    # (e.g., date_deceased, deceased_date) without needing strict schema knowledge.
    if expected_dod in db_dump:
        score += 50
        feedback_parts.append(f"Date of Death '{expected_dod}' found in record")
    else:
        feedback_parts.append(f"Date of Death '{expected_dod}' NOT found in record")

    # Criterion 3: Status/Deceased Indicator (30 pts)
    # Look for common indicators in the dump
    deceased_indicators = [
        "deceased: 1", 
        "deceased: y", 
        "deceased: true",
        "active: 0", 
        "active: false"
    ]
    
    # Also if the date of death is present, usually implies deceased status in NOSH logic
    status_found = False
    
    # Check text indicators (case insensitive)
    db_dump_lower = db_dump.lower()
    for ind in deceased_indicators:
        if ind in db_dump_lower:
            status_found = True
            break
            
    # If date is set, we also count status as updated for scoring purposes 
    # (as date entry is the primary goal)
    if expected_dod in db_dump:
        status_found = True

    if status_found:
        score += 30
        feedback_parts.append("Deceased status indicated")
    else:
        feedback_parts.append("Deceased status NOT clearly indicated (check 'active' or 'deceased' fields)")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }