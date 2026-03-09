#!/usr/bin/env python3
"""
Verifier for delete_patient_record task.

Criteria:
1. Target patient (Marcus Wellington) must be deleted from CouchDB (404 or _deleted: true).
2. Control patient (Elena Vasquez) must still exist.
3. VLM: Trajectory must show navigation to patient and interaction with Delete button/modal.
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_patient_record(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 2. Database Verification (50 points total)
    
    # Check Target Deletion (35 pts)
    target_deleted = result.get("target_deleted", False)
    target_existed_start = result.get("target_existed_at_start", False)
    
    if target_deleted and target_existed_start:
        score += 35
        feedback_parts.append("Target patient 'Marcus Wellington' successfully deleted.")
    elif not target_existed_start:
        feedback_parts.append("Setup error: Target patient did not exist at start.")
    else:
        feedback_parts.append("Target patient 'Marcus Wellington' still exists in database.")

    # Check Control Preservation (15 pts)
    control_exists = result.get("control_exists", False)
    if control_exists:
        score += 15
        feedback_parts.append("Control patient 'Elena Vasquez' preserved.")
    else:
        feedback_parts.append("CRITICAL: Control patient 'Elena Vasquez' was accidentally deleted!")

    # 3. VLM Verification (50 points total)
    # We need to confirm the agent actually did the work in the UI, not just curl commands (anti-gaming)
    # and to confirm they handled the modal.
    
    frames = sample_trajectory_frames(traj, n=5)
    
    prompt = """
    You are verifying an agent's actions in HospitalRun. The task was to DELETE a patient named 'Marcus Wellington'.
    
    Look at the sequence of screenshots.
    1. Did the agent navigate to the Patient List or Search for 'Marcus'?
    2. Did the agent open a patient record?
    3. Is the 'Delete' button or a Delete Confirmation Modal visible in any frame?
    4. Does the UI show 'Marcus Wellington' being viewed/deleted?
    
    Return JSON:
    {
        "patient_found": boolean,
        "delete_action_visible": boolean, 
        "confirmation_modal_visible": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result and vlm_result.get('success'):
        analysis = vlm_result.get('parsed', {})
        
        # Points for finding/opening the patient
        if analysis.get('patient_found', False):
            score += 15
            feedback_parts.append("VLM: Patient record accessed.")
        
        # Points for attempting deletion (button or modal)
        if analysis.get('delete_action_visible', False) or analysis.get('confirmation_modal_visible', False):
            score += 35
            feedback_parts.append("VLM: Delete action/confirmation observed.")
        else:
            feedback_parts.append("VLM: No visible deletion action (button click or modal) observed.")
    else:
        # Fallback if VLM fails but DB is correct
        if target_deleted:
            score += 25
            feedback_parts.append("VLM failed but DB confirms deletion (partial credit).")

    # 4. Final Scoring
    passed = (score >= 60) and target_deleted and control_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }