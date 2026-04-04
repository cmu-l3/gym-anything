#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transfer_patient(traj, env_info, task_info):
    """
    Verifies that patient Li Wei was transferred to ICU.
    
    Criteria:
    1. Visit document exists.
    2. Location is 'Intensive Care Unit' (case-insensitive).
    3. Status is still 'Admitted' (not Discharged).
    4. Patient linkage is preserved.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Document Data
    # HospitalRun CouchDB docs wrap content in a "data" key, but sometimes raw.
    # The setup script creates it wrapped in "data".
    raw_doc = result.get("visit_doc", {})
    
    # Handle the "data" wrapper common in HR
    visit_data = raw_doc.get("data", raw_doc)
    
    # If the doc wasn't found (e.g. 404), raw_doc might be just {"error":"not_found"}
    if not visit_data or "location" not in visit_data:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The visit record for Li Wei could not be found in the database. Did you accidentally delete it?"
        }

    # 3. Evaluate Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Check Location (40 pts)
    # Flexible matching for "ICU" or "Intensive Care Unit"
    actual_location = visit_data.get("location", "").strip()
    target_location = "Intensive Care Unit"
    
    if target_location.lower() in actual_location.lower() or "icu" in actual_location.lower():
        score += 40
        feedback.append("Success: Location updated to Intensive Care Unit.")
    else:
        feedback.append(f"Fail: Location is '{actual_location}', expected '{target_location}'.")

    # Criterion 2: Check Status (30 pts)
    # Must remain "Admitted". If they discharged him, it fails this check.
    actual_status = visit_data.get("status", "").strip()
    if actual_status.lower() == "admitted":
        score += 30
        feedback.append("Success: Patient status remains Admitted.")
    else:
        feedback.append(f"Fail: Patient status changed to '{actual_status}' (should be 'Admitted').")

    # Criterion 3: Visit Integrity (30 pts)
    # Check patient link and reason
    patient_ref = visit_data.get("patient", "")
    reason = visit_data.get("reasonForVisit", "")
    
    if "liwei" in patient_ref and "Pneumonia" in reason:
        score += 30
        feedback.append("Success: Visit record integrity maintained.")
    else:
        feedback.append("Fail: Visit record seems to have lost patient linkage or data.")

    # 4. Final Verdict
    # Need correct location AND correct status to pass
    passed = (score >= 70) and ("Fail: Location" not in str(feedback)) and ("Fail: Patient status" not in str(feedback))

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }