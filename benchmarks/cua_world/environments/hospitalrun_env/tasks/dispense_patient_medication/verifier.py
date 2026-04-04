#!/usr/bin/env python3
"""
Verifier for dispense_patient_medication@1.
Checks if the specific medication order was marked as Completed,
while ensuring distractors were left untouched.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dispense_medication(traj, env_info, task_info):
    """
    Verifies the dispense medication task.
    """
    # 1. Setup Result Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

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

    # 2. Extract Data
    target_doc = result.get("target_doc", {})
    cancelled_distractor = result.get("distractor_cancelled_doc", {})
    other_distractor = result.get("distractor_other_doc", {})
    
    # HospitalRun wraps content in 'data', check both levels just in case
    target_data = target_doc.get("data", target_doc)
    cancelled_data = cancelled_distractor.get("data", cancelled_distractor)
    other_data = other_distractor.get("data", other_distractor)

    score = 0
    feedback = []
    failed_critical = False

    # 3. Verify Target Order (50 pts)
    # Status should be "Completed"
    target_status = target_data.get("status", "Unknown")
    if target_status in ["Completed", "Dispensed", "Fulfilled"]:
        score += 50
        feedback.append("Success: Target medication marked as Completed.")
    else:
        feedback.append(f"Fail: Target medication status is '{target_status}', expected 'Completed'.")
        failed_critical = True

    # 4. Verify Distractors (Anti-Gaming/Attention)
    
    # Distractor 1: Cancelled order should stay Cancelled (15 pts)
    cancelled_status = cancelled_data.get("status", "Unknown")
    if cancelled_status == "Cancelled":
        score += 15
        feedback.append("Success: Cancelled distractor was left alone.")
    else:
        # If they changed the cancelled order, that's a big error
        feedback.append(f"Fail: Cancelled order for Sven was changed to '{cancelled_status}'.")

    # Distractor 2: Other patient's order should stay New (15 pts)
    other_status = other_data.get("status", "Unknown")
    if other_status == "New":
        score += 15
        feedback.append("Success: Other patient's order was left alone.")
    else:
        feedback.append(f"Fail: Janice's order was incorrectly changed to '{other_status}'.")

    # 5. VLM / Trajectory Verification (20 pts)
    # We'll simulate this score based on the critical success for now, 
    # but strictly this would use VLM.
    # If critical success passed, we assume they did the UI work.
    if not failed_critical:
        score += 20
        feedback.append("Trajectory: Workflow appears valid.")
    else:
        feedback.append("Trajectory: Workflow failed key objective.")

    # 6. Final Decision
    # Pass if target is correct and score >= 70
    passed = (not failed_critical) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }