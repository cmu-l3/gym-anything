#!/usr/bin/env python3
import json
import logging
import os
import sys

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_admit_patient(traj, env_info, task_info):
    """
    Verifies that Sarah Connor was admitted to the Surgical Ward.
    
    Scoring Criteria:
    1. Visit Record Exists (30 pts)
    2. Linked to Sarah Connor (20 pts)
    3. Visit Type is 'Admission' or 'Inpatient' (20 pts)
    4. Location is 'Surgical Ward' (15 pts)
    5. Diagnosis/Reason contains 'Appendicitis' (15 pts)
    """
    
    # 1. Setup & Data Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
    
    # Load result file
    import tempfile
    tmp_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
            
    # Extract DB result
    db_res = result_data.get("db_result", {})
    visit_doc = db_res.get("visit_doc")
    
    score = 0
    feedback = []
    
    # 2. Verify Record Existence
    if not db_res.get("visit_found") or not visit_doc:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No visit record found for patient Sarah Connor."
        }
    
    score += 30
    feedback.append("Visit record created.")
    
    # 3. Verify Patient Link (Implicitly handled by export query, but good to confirm)
    # The export script filtered by patient ID, so if we have a doc, it's linked.
    score += 20
    feedback.append("Linked to correct patient.")

    # 4. Verify Visit Type
    # HospitalRun keys might vary slightly, check standard ones
    v_type = visit_doc.get("visitType", "").lower()
    if "admission" in v_type or "inpatient" in v_type:
        score += 20
        feedback.append(f"Visit Type correct: {visit_doc.get('visitType')}")
    else:
        feedback.append(f"Incorrect Visit Type: expected 'Admission', got '{visit_doc.get('visitType')}'")
        
    # 5. Verify Location
    # Location might be 'location' field
    loc = visit_doc.get("location", "").lower()
    if "surgical" in loc:
        score += 15
        feedback.append(f"Location correct: {visit_doc.get('location')}")
    else:
        feedback.append(f"Incorrect Location: expected 'Surgical Ward', got '{visit_doc.get('location')}'")
        
    # 6. Verify Diagnosis/Reason
    # Could be in 'reasonForVisit', 'diagnosis', or 'reason'
    reason = visit_doc.get("reasonForVisit", "")
    diagnosis = visit_doc.get("diagnosis", "")
    full_text = (str(reason) + " " + str(diagnosis)).lower()
    
    if "appendicitis" in full_text:
        score += 15
        feedback.append("Diagnosis/Reason correct.")
    else:
        feedback.append(f"Diagnosis missing or incorrect. Found: '{reason}' / '{diagnosis}'")

    # 7. VLM Trajectory Check (Bonus/Verification)
    # We can perform a quick check if score is borderline, but relying on DB is safer for exact strings.
    # If the score is high (passed programmatically), we trust it.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }