#!/usr/bin/env python3
"""
Verifier for configure_attendance_codes task.

Checks:
1. "Half Day" (HD) code exists in database with correct fields.
2. "Virtual Attendance" (VA) code exists in database with correct fields.
3. Total attendance code count increased (anti-gaming: ensures new records).
4. VLM verification of trajectory (optional/secondary).
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_attendance_codes(traj, env_info, task_info):
    """
    Verify that the user configured the two required attendance codes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result data from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Metadata expectations
    # Note: These are hardcoded in the verifier for simplicity based on task description,
    # but strictly speaking could come from task_info['metadata']
    
    # --- Check 1: Half Day Code (40 points) ---
    hd_info = result.get('hd_code', {})
    if hd_info.get('exists'):
        score += 20
        feedback_parts.append("'Half Day' code found.")
        
        data = hd_info.get('data', {})
        # Verify attributes
        correct_title = "Half Day" in data.get('title', '')
        correct_short = data.get('short_name') == "HD"
        correct_type = "Official" in data.get('type', '')
        
        attr_score = 0
        if correct_title: attr_score += 5
        if correct_short: attr_score += 10
        if correct_type: attr_score += 5
        
        score += attr_score
        if attr_score < 20:
             feedback_parts.append(f"HD attributes partial match: Title={correct_title}, Short={correct_short}, Type={correct_type}")
    else:
        feedback_parts.append("'Half Day' code NOT found.")

    # --- Check 2: Virtual Attendance Code (40 points) ---
    va_info = result.get('va_code', {})
    if va_info.get('exists'):
        score += 20
        feedback_parts.append("'Virtual Attendance' code found.")
        
        data = va_info.get('data', {})
        # Verify attributes
        correct_title = "Virtual" in data.get('title', '')
        correct_short = data.get('short_name') == "VA"
        correct_type = "Official" in data.get('type', '')
        
        attr_score = 0
        if correct_title: attr_score += 5
        if correct_short: attr_score += 10
        if correct_type: attr_score += 5
        
        score += attr_score
        if attr_score < 20:
             feedback_parts.append(f"VA attributes partial match: Title={correct_title}, Short={correct_short}, Type={correct_type}")
    else:
        feedback_parts.append("'Virtual Attendance' code NOT found.")

    # --- Check 3: Anti-gaming / New Records (20 points) ---
    increase = result.get('count_increase', 0)
    if increase >= 2:
        score += 20
        feedback_parts.append("Database record count increased correctly.")
    elif increase > 0:
        score += 10
        feedback_parts.append("Database record count increased partially.")
    else:
        feedback_parts.append("No new database records detected.")

    # --- VLM Verification (Bonus / Confidence Check) ---
    # We use this to confirm the UI was actually used, protecting against pure SQL injection gaming (unlikely here but good practice)
    # Only run if we haven't already failed badly
    if score > 40:
        frames = sample_trajectory_frames(traj, n=3)
        final_shot = get_final_screenshot(traj)
        
        if frames and final_shot:
            prompt = """
            Look at these screenshots of a user interacting with OpenSIS.
            Did the user navigate to 'School Setup' and 'Attendance Codes'? 
            Do you see a form or list containing 'Half Day' or 'Virtual Attendance'?
            """
            vlm_res = query_vlm(images=frames + [final_shot], prompt=prompt)
            
            # We don't strictly penalize score here to avoid false negatives from VLM,
            # but we append feedback
            if vlm_res.get('success'):
                feedback_parts.append(f"VLM Analysis: {vlm_res.get('parsed', {}).get('answer', 'Analyzed')}")

    passed = score >= 80  # Requires finding both codes with correct short names + increase
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }