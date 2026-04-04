#!/usr/bin/env python3
"""
Verifier for discharge_patient task.

Criteria:
1. Visit Status must be "Discharged".
2. End Date must match "2025-01-17" (formatted).
3. Document revision must differ from initial (proof of edit).
4. Patient linkage must remain intact.
"""

import json
import os
import sys
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discharge_patient(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load expected values
    metadata = task_info.get("metadata", {})
    expected_status = metadata.get("expected_status", "Discharged")
    expected_date_fragment = metadata.get("expected_end_date_fragment", "2025-01-17")

    # 2. Retrieve Result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Check 1: Visit exists (Basic sanity)
    if not result.get("visit_exists"):
        return {"passed": False, "score": 0, "feedback": "Visit document was deleted or not found."}

    # Check 2: Status is Discharged (35 pts)
    actual_status = result.get("status", "")
    if actual_status.lower() == expected_status.lower():
        score += 35
        feedback.append("Status updated to Discharged.")
    else:
        feedback.append(f"Status mismatch: Expected '{expected_status}', got '{actual_status}'.")

    # Check 3: End Date is correct (25 pts)
    # HospitalRun saves dates as ISO strings or timestamps usually. 
    # We check if our target date string is inside the result.
    actual_date = str(result.get("end_date", ""))
    
    # Normalize inputs for comparison if possible, or just strict substring check
    # The UI date picker usually saves exactly what is entered if simple string, or ISO if object.
    # We accept "2025-01-17" or "01/17/2025" logic.
    date_correct = False
    if expected_date_fragment in actual_date:
        date_correct = True
    elif "01/17/2025" in actual_date:
        date_correct = True
    # Handle JS timestamp/ISO potentially
    elif "1737072000000" in actual_date: # Approx TS for 2025-01-17
        date_correct = True
        
    if date_correct:
        score += 25
        feedback.append("Discharge date set correctly.")
    else:
        feedback.append(f"Date mismatch: Expected '{expected_date_fragment}' or equivalent, got '{actual_date}'.")

    # Check 4: Anti-Gaming - Document was actually updated (15 pts)
    initial_rev = result.get("initial_rev", "missing")
    current_rev = result.get("visit_rev", "missing")
    
    if initial_rev and current_rev and initial_rev != current_rev:
        score += 15
        feedback.append("Visit record was modified.")
    else:
        feedback.append("Visit record revision unchanged (No edits detected).")

    # Check 5: Integrity - Patient Linkage (15 pts)
    patient_ref = result.get("visit_patient_ref", "")
    expected_patient_id = metadata.get("patient_id", "patient_p1_200001")
    
    if expected_patient_id in patient_ref:
        score += 15
        feedback.append("Patient linkage preserved.")
    else:
        feedback.append("Error: Visit is no longer linked to the correct patient.")

    # Check 6: Integrity - Patient Name (10 pts)
    patient_name = result.get("patient_name", "")
    if "Maria Santos" in patient_name:
        score += 10
        feedback.append("Patient record intact.")
    else:
        feedback.append(f"Patient record data mismatch: '{patient_name}'.")

    # 4. Final Verdict
    # Threshold: 70 points. Must have Status change AND Date change to be useful.
    passed = (score >= 70) and (actual_status.lower() == expected_status.lower()) and date_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }