#!/usr/bin/env python3
"""
Verifier for update_employee_visa_details task.

Verifies:
1. Database contains the correct Visa record (Number, Expiry).
2. Database contains the document attachment reference.
3. VLM trajectory verification (optional/bonus).
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_employee_visa_details(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container (Windows path)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: copy_from_env usually handles the path translation, but we specify the internal Windows path
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Database Verification
    visa_count = result.get('visa_record_count', 0)
    doc_count = result.get('doc_record_count', 0)
    app_running = result.get('app_was_running', False)

    if visa_count > 0:
        score += 40
        feedback.append("Visa record found in database.")
    else:
        feedback.append("Visa record NOT found or incorrect details.")

    if doc_count > 0:
        score += 30
        feedback.append("Document attachment found in database.")
    else:
        feedback.append("Document attachment NOT found.")

    if app_running:
        score += 10
        feedback.append("Application was running.")

    # 3. VLM Verification (Trajectory)
    # We look for the "Visa" tab usage and "Open File" dialog
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with AttendHRM.
    Look for two specific actions:
    1. Entering Visa details (look for 'Visa', 'Passport', dates, or number 'V987654321').
    2. Uploading a document (look for a file dialog selecting 'maria_visa_scan' or a documents list).
    
    Did the agent perform these actions?
    """
    
    vlm_result = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
    
    vlm_passed = False
    if vlm_result.get('success'):
        # Simple heuristic check on VLM output
        response_text = vlm_result.get('parsed', {}).get('response', '').lower()
        if "yes" in response_text or "performed" in response_text:
            score += 20
            vlm_passed = True
            feedback.append("VLM confirmed workflow actions.")
        else:
            feedback.append("VLM could not verify workflow.")
    else:
        # Fallback if VLM fails/is unavailable, grant partial points if DB passed
        if visa_count > 0 and doc_count > 0:
            score += 10
            feedback.append("VLM skipped, implicit pass based on DB data.")

    # 4. Final Score Calculation
    passed = (score >= 70) and (visa_count > 0) and (doc_count > 0)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }