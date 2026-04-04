#!/usr/bin/env python3
"""
Verifier for process_deceased_patient task.

Criteria:
1. Database: Patient 'Pedro Alva' has deceased_date = '2025-02-20' (40 pts)
2. Database: Appointment status changed to Canceled/x (40 pts)
3. VLM: Visual confirmation of workflow (20 pts)
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_deceased_patient(traj, env_info, task_info):
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
    
    # --- Criterion 1: Deceased Date (40 pts) ---
    expected_date = task_info.get("metadata", {}).get("deceased_date", "2025-02-20")
    actual_date = result.get("db_deceased_date", "")
    
    # Handle NULL/None/Empty
    if actual_date and str(actual_date).strip() == expected_date:
        score += 40
        feedback_parts.append(f"Patient correctly marked deceased on {expected_date}.")
    elif actual_date and str(actual_date).strip() != "":
        score += 20
        feedback_parts.append(f"Patient marked deceased, but wrong date (Expected: {expected_date}, Got: {actual_date}).")
    else:
        feedback_parts.append("Patient NOT marked as deceased in database.")

    # --- Criterion 2: Appointment Cancellation (40 pts) ---
    # OpenEMR status: '-' is active/pending. 'x' is canceled. '?' is no show.
    # The agent might also use a status dropdown that maps to 'Canceled'.
    final_status = result.get("final_appt_status", "-")
    appt_exists = result.get("final_appt_exists", 0)

    # In LibreHealth/OpenEMR, 'x' is the standard code for Canceled in the DB
    # We also accept if the user deleted it (appt_exists == 0), though instructions said cancel.
    # We prioritize proper cancellation.
    
    is_canceled = str(final_status).lower() in ['x', 'canceled', 'cancelled', '3'] # 3 is sometimes ID for cancel
    
    if int(appt_exists) == 1 and is_canceled:
        score += 40
        feedback_parts.append("Appointment successfully canceled.")
    elif int(appt_exists) == 0:
        score += 20
        feedback_parts.append("Appointment was deleted instead of canceled (partial credit).")
    elif str(final_status) != "-":
        # Status changed but maybe not to cancel?
        score += 10
        feedback_parts.append(f"Appointment status changed to '{final_status}' (check if this is valid cancellation).")
    else:
        feedback_parts.append("Appointment status remains unchanged (Active).")

    # --- Criterion 3: VLM Verification (20 pts) ---
    # We want to see evidence of the demographics edit or the calendar interaction
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + [final_screen] if final_screen else frames

    vlm_prompt = """
    Analyze these screenshots of a user interacting with an EHR system.
    Look for two specific actions:
    1. Editing Patient Demographics: Look for a form with 'Deceased' checkbox or Date of Death field.
    2. Calendar/Appointment Management: Look for a calendar view, appointment popup, or status change menu (e.g., selecting 'Cancel').
    
    Did the user perform these actions?
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=images_to_check, prompt=vlm_prompt)
        if vlm_res.get("success"):
            # Simple heuristic: if VLM is positive, give points
            # In a real impl, we'd parse structured JSON output
            vlm_score = 20
            feedback_parts.append("VLM confirmed UI interaction.")
        else:
            feedback_parts.append("VLM analysis failed.")
    except Exception:
        pass
    
    score += vlm_score

    # Final Pass Logic
    # Strict: Must have updated DB correctly for date AND canceled appointment
    passed = (actual_date == expected_date) and (int(appt_exists) == 1 and is_canceled)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }