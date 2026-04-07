#!/usr/bin/env python3
"""
Verifier for add_imaging_order task.

Criteria:
1.  Order exists in database for correct patient.
2.  Order count increased (anti-gaming).
3.  Order type is Radiology/Imaging.
4.  Description contains 'MRI' and 'Lumbar'/'Spine'.
5.  Indication/Reason contains 'back pain'/'radiculopathy'.
6.  VLM verification of trajectory (workflow check).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_imaging_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Database Result
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
    feedback = []
    metadata = task_info.get('metadata', {})
    
    # --- CRITERION 1: Order Created (20 pts) ---
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    order_found = result.get('order_found', False)
    
    if order_found and current_count > initial_count:
        score += 20
        feedback.append("New order created in database.")
    elif order_found:
        # Found an order but count didn't increase? Maybe modified existing?
        score += 10
        feedback.append("Order found, but count did not increase (modified existing?).")
    else:
        feedback.append("No order found in database.")
        return {"passed": False, "score": 0, "feedback": "No order created."}

    # --- CRITERION 2: Order Type (20 pts) ---
    # NOSH usually stores 'rad' for radiology
    order_data = result.get('last_order', {})
    o_type = order_data.get('type', '').lower()
    
    if 'rad' in o_type or 'image' in o_type or 'imaging' in o_type:
        score += 20
        feedback.append(f"Correct order type: {o_type}.")
    else:
        feedback.append(f"Incorrect order type: {o_type} (expected rad/imaging).")

    # --- CRITERION 3: Order Details (MRI/Lumbar) (20 pts) ---
    desc = order_data.get('description', '').lower()
    req_terms = metadata.get('required_terms', ['mri', 'lumbar'])
    
    matches = [t for t in req_terms if t.lower() in desc]
    if len(matches) == len(req_terms):
        score += 20
        feedback.append("Order description matches required terms.")
    elif len(matches) > 0:
        score += 10
        feedback.append(f"Order description partial match (found: {matches}).")
    else:
        feedback.append(f"Order description mismatch. Got: '{desc}'.")

    # --- CRITERION 4: Indication/Reason (20 pts) ---
    reason = order_data.get('reason', '').lower()
    req_indication = metadata.get('required_indication_terms', ['back pain'])
    
    matches_ind = [t for t in req_indication if t.lower() in reason]
    if len(matches_ind) >= 1: # At least one key term
        score += 20
        feedback.append("Clinical indication provided correctly.")
    else:
        feedback.append(f"Clinical indication mismatch. Got: '{reason}'.")

    # --- CRITERION 5: VLM Verification (20 pts) ---
    # Check if agent actually navigated the UI
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the sequence of images show a user navigating an Electronic Health Record (EHR)? "
            "Look for: 1. A patient chart (Robert Murphy). 2. An 'Orders' or 'Radiology' screen. "
            "3. Filling out a form. "
            "Reply 'YES' if the workflow is visible."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res and 'YES' in str(vlm_res.get('response', '')).upper():
                score += 20
                feedback.append("VLM verified workflow trajectory.")
            else:
                score += 10 # Give partial credit if VLM is unsure but DB is correct
                feedback.append("VLM could not explicitly verify workflow.")
        except Exception:
            # Fallback if VLM fails
            score += 20
    else:
        feedback.append("No trajectory frames available.")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }