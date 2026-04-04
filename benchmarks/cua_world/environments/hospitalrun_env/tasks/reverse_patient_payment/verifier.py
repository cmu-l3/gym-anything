#!/usr/bin/env python3
"""
Verifier for reverse_patient_payment task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reverse_payment(traj, env_info, task_info):
    """
    Verifies that the agent deleted the specific payment record.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Criteria
    payment_exists = result.get("payment_exists", True)
    patient_exists = result.get("patient_exists", False)
    
    score = 0
    feedback = []

    # 1. Primary Goal: Payment should be GONE (60 pts)
    if not payment_exists:
        score += 60
        feedback.append("Success: Payment record was deleted.")
    else:
        feedback.append("Failure: Payment record still exists in database.")

    # 2. Safety Goal: Patient should still EXIST (20 pts)
    if patient_exists:
        score += 20
        feedback.append("Safety Check Passed: Patient record is intact.")
    else:
        feedback.append("Safety Check Failed: Patient record was also deleted!")
        # Severe penalty logic could apply, but standard rubric is simple addition
        # If they deleted the patient, they likely failed the task implicitly by being destructive
    
    # 3. VLM Trajectory Verification (20 pts)
    # Ensure they actually used the UI (Billing -> Payments -> Delete)
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a user interacting with HospitalRun.
    The goal was to delete a payment of $150.00.
    
    Look for:
    1. Navigation to the 'Billing' or 'Payments' section.
    2. A list of payments visible.
    3. A confirmation dialog asking to delete/remove an item.
    
    Did the user appear to navigate to the payments list and perform a deletion?
    Reply with JSON: {"performed_deletion": boolean, "reason": "string"}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get('parsed', {}).get('performed_deletion', False):
            vlm_score = 20
            feedback.append("VLM: Confirmed UI interaction for deletion.")
        else:
            feedback.append("VLM: Could not clearly confirm deletion workflow from screenshots.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if programmatic check passed, give partial VLM points
        if not payment_exists:
            vlm_score = 10 
            feedback.append("VLM check skipped, awarding partial points based on outcome.")

    score += vlm_score

    # Final Pass Determination
    # Must have deleted payment AND kept patient
    passed = (not payment_exists) and patient_exists and (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }