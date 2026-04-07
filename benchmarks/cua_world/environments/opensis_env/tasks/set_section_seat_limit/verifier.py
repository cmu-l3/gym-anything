#!/usr/bin/env python3
"""
Verifier for set_section_seat_limit task.

Criteria:
1. Target Course (ART-205) seats must be 12 (40 pts).
2. Control Course (ART-101) seats must remain 25 (20 pts).
3. Navigation/Process verification via VLM (40 pts).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_section_seat_limit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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
    
    # Metadata targets
    target_val = int(task_info.get('metadata', {}).get('target_seats', 12))
    control_val = int(task_info.get('metadata', {}).get('control_seats', 25))

    # --- Criterion 1: Target Check (40 pts) ---
    try:
        actual_target = int(result.get('target_seats', -1))
    except (ValueError, TypeError):
        actual_target = -1

    if actual_target == target_val:
        score += 40
        feedback.append("Success: Ceramics capacity updated to 12.")
    elif actual_target != -1 and actual_target != 25:
        # Changed but wrong value (Partial credit)
        score += 10
        feedback.append(f"Partial: Capacity changed to {actual_target}, expected {target_val}.")
    else:
        feedback.append(f"Fail: Ceramics capacity is {actual_target} (expected {target_val}).")

    # --- Criterion 2: Control Check (Anti-Gaming) (20 pts) ---
    try:
        actual_control = int(result.get('control_seats', -1))
    except (ValueError, TypeError):
        actual_control = -1

    if actual_control == control_val:
        score += 20
        feedback.append("Success: Other courses were not modified.")
    else:
        feedback.append(f"Fail: Control course (Drawing) was modified to {actual_control}.")

    # --- Criterion 3: VLM Process Verification (40 pts) ---
    # We want to see evidence of the scheduling module/form
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    You are verifying an agent's workflow in OpenSIS.
    The goal was to update the seat limit for a course section.
    
    Look at these screenshots sequence. Do you see:
    1. The OpenSIS interface?
    2. Navigation to 'Scheduling' or 'Courses'?
    3. A form or list showing 'Introduction to Ceramics' or 'ART-205'?
    4. An input field for 'Seats' or 'Capacity' being edited?
    
    Answer JSON: {"valid_workflow": bool, "reason": "..."}
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('valid_workflow', False):
                score += 40
                feedback.append("VLM: Valid workflow detected.")
            else:
                feedback.append(f"VLM: Workflow unclear ({parsed.get('reason', 'unknown')}).")
        else:
            # Fallback if VLM fails but data is correct
            if score >= 60:
                score += 40
                feedback.append("VLM skipped but data correct.")
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        # Graceful fallback
        if score >= 60:
            score += 40

    # Final tally
    passed = score >= 90  # Strict pass: Must get value correct + safety + reasonable workflow
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }