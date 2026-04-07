#!/usr/bin/env python3
"""
Verifier for update_employee_identity task.
Checks:
1. Employee 'Anita Oliver' exists.
2. Profile photo is set (binary field not empty).
3. Badge ID is exactly 'AO-9942'.
4. Record was modified AFTER task start time (anti-gaming).
5. VLM trajectory check for UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_employee_identity(traj, env_info, task_info):
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

    score = 0
    feedback_parts = []
    
    # Extract data
    task_start = result.get("task_start", 0)
    odoo_state = result.get("odoo_state", {})
    
    emp_found = odoo_state.get("employee_found", False)
    image_present = odoo_state.get("image_present", False)
    barcode_value = odoo_state.get("barcode_value", "")
    write_ts = odoo_state.get("write_date_ts", 0)

    # Criterion 1: Employee Found (10 pts)
    if emp_found:
        score += 10
        feedback_parts.append("Employee record found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Employee 'Anita Oliver' not found in database."}

    # Criterion 2: Anti-gaming Timestamp Check (10 pts)
    # Note: Odoo stores times in UTC, task_start is UNIX TS. 
    # write_ts comes from python conversion of Odoo's string.
    # Allowing a small skew buffer if clocks slightly off, but usually Odoo internal clock is consistent.
    if write_ts >= task_start:
        score += 10
        feedback_parts.append("Record modified during task.")
    else:
        feedback_parts.append(f"Record NOT modified during task (Write: {write_ts}, Start: {task_start}).")

    # Criterion 3: Image Uploaded (35 pts)
    if image_present:
        score += 35
        feedback_parts.append("Profile photo uploaded.")
    else:
        feedback_parts.append("Profile photo is missing.")

    # Criterion 4: Badge ID Correct (35 pts)
    expected_badge = task_info.get("metadata", {}).get("target_badge_id", "AO-9942")
    if str(barcode_value).strip() == expected_badge:
        score += 35
        feedback_parts.append(f"Badge ID correct ({expected_badge}).")
    else:
        feedback_parts.append(f"Badge ID incorrect. Expected '{expected_badge}', found '{barcode_value}'.")

    # Criterion 5: VLM Trajectory Verification (10 pts)
    # We want to see the file upload dialog or the form being edited
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a user interacting with Odoo HR.
    I am looking for evidence that the user:
    1. Opened the file selection/upload dialog (system window).
    2. Viewed or edited the profile of "Anita Oliver".
    3. The final state shows an avatar image (not a grey placeholder) and Badge ID "AO-9942".
    
    Return JSON: {"evidence_found": boolean, "confidence": "high/medium/low"}
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("evidence_found"):
                vlm_score = 10
                feedback_parts.append("VLM confirms workflow.")
            else:
                feedback_parts.append("VLM could not visually confirm workflow.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final Pass Check
    # Must have image AND correct badge AND modified timestamp to pass
    passed = (image_present and 
              str(barcode_value).strip() == expected_badge and 
              write_ts >= task_start and
              score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }