#!/usr/bin/env python3
"""
Verifier for mark_patient_deceased task.
Checks if the specific patient document in CouchDB has been updated 
with deceased=true and the correct date of death.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mark_patient_deceased(traj, env_info, task_info):
    """
    Verifies that Eleanor Rigby is marked as deceased with DOD 11/11/2025.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_dod_iso = metadata.get('expected_dod', "2025-11-11") # YYYY-MM-DD
    
    # Load result from container
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

    # Extract patient document
    patient_doc = result.get('patient_doc', {})
    if not patient_doc or 'error' in patient_doc:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Patient document not found in database (or deleted)."
        }

    # HospitalRun data is usually inside a 'data' wrapper
    data = patient_doc.get('data', patient_doc)

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check Deceased Status (50 points)
    # Could be boolean true or string "true"
    is_deceased = data.get('deceased')
    
    # Normalize to boolean
    if str(is_deceased).lower() == 'true':
        is_deceased_bool = True
    else:
        is_deceased_bool = bool(is_deceased)

    if is_deceased_bool:
        score += 50
        feedback_parts.append("Patient correctly marked as deceased.")
    else:
        feedback_parts.append("Patient is NOT marked as deceased.")

    # 2. Check Date of Death (50 points)
    # Field names can vary slightly in HR versions, usually 'dateOfDeath' or 'deathDate'
    dod_value = data.get('dateOfDeath') or data.get('deathDate')
    
    if dod_value:
        # Check if the expected date string is part of the stored value
        # (Stored value might be full ISO timestamp e.g. 2025-11-11T00:00:00.000Z)
        if expected_dod_iso in str(dod_value):
            score += 50
            feedback_parts.append(f"Date of Death correct ({expected_dod_iso}).")
        else:
            feedback_parts.append(f"Date of Death mismatch. Expected ~{expected_dod_iso}, got '{dod_value}'.")
    else:
        if is_deceased_bool:
            feedback_parts.append("Date of Death is missing.")
    
    # Final check
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }