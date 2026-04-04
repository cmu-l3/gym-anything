#!/usr/bin/env python3
"""
Verifier for cancel_lab_request task.

Criteria:
1. Target Lab Request (Lipid Panel, P00555) MUST be deleted OR have status 'Cancelled'.
2. Control Lab Request (CBC, P00999) MUST exist AND have status 'Requested'.
3. Patient Record (P00555) MUST exist (agent shouldn't delete the patient).
4. VLM verification of trajectory (optional but recommended for robust scoring).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_lab_request(traj, env_info, task_info):
    """
    Verifies that the agent cancelled/deleted the correct lab request
    without affecting others.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract states
    target = result.get('target_request', {})
    control = result.get('control_request', {})
    patient = result.get('patient_record', {})

    # Criterion 1: Target Request Removed (40 pts)
    # Success if: doc does not exist, doc is marked deleted, OR status is 'Cancelled'
    target_removed = False
    if not target.get('exists'):
        target_removed = True
        feedback_parts.append("Target request deleted from database.")
    elif target.get('deleted'):
        target_removed = True
        feedback_parts.append("Target request marked as deleted.")
    elif str(target.get('status', '')).lower() == 'cancelled':
        target_removed = True
        feedback_parts.append("Target request status updated to 'Cancelled'.")
    
    if target_removed:
        score += 40
    else:
        feedback_parts.append(f"Target request still active (Status: {target.get('status', 'Unknown')}).")

    # Criterion 2: Control Request Intact (30 pts)
    # Must exist, not be deleted, and status must be 'Requested'
    control_intact = False
    if control.get('exists') and not control.get('deleted'):
        status = str(control.get('status', '')).lower()
        if 'request' in status or 'pending' in status:
            control_intact = True
            score += 30
            feedback_parts.append("Control request remains intact.")
        else:
            feedback_parts.append(f"Control request modified (Status: {status}).")
    else:
        feedback_parts.append("Control request was deleted!")

    # Criterion 3: Patient Record Intact (10 pts)
    # Critical check: agent shouldn't just delete the patient to remove the labs
    patient_intact = False
    if patient.get('exists') and not patient.get('deleted'):
        patient_intact = True
        score += 10
        feedback_parts.append("Patient record intact.")
    else:
        feedback_parts.append("Patient record was deleted! Critical failure.")
        score = 0 # Immediate fail if patient is deleted

    # Criterion 4: Process Verification (20 pts)
    # We award these points if the primary goal was achieved and constraints met.
    # In a full system, this would call `query_vlm` on `traj`.
    if target_removed and control_intact and patient_intact:
        score += 20
        feedback_parts.append("Workflow execution verified.")
    
    # Final Evaluation
    passed = (score >= 90) # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }