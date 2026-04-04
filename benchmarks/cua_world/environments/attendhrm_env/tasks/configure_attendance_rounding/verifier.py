#!/usr/bin/env python3
"""
Verifier for configure_attendance_rounding task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_attendance_rounding(traj, env_info, task_info):
    """
    Verifies the attendance rounding configuration.
    
    Strategy:
    1. Try to read the DB result exported by the Windows script.
    2. Use VLM to verify the UI interaction (essential if DB query fails or for confirmation).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Parsing Programmatic Result (DB Query)
    programmatic_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Windows path inside container -> local temp file
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            programmatic_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Score calculation
    score = 0
    feedback_parts = []
    
    # DB Verification (Primary)
    # Mapping: '2' often means 'Nearest', '1' might be 'Down', '3' 'Up'. 
    # We allow flexible matching if we get raw codes or strings.
    db_connected = programmatic_result.get('db_connected', False)
    
    # Expected values
    expected_val = 5
    # If DB return "2" or "Nearest"
    in_method = str(programmatic_result.get('rounding_in_method', '')).strip().lower()
    in_value = int(programmatic_result.get('rounding_in_value', 0))
    out_method = str(programmatic_result.get('rounding_out_method', '')).strip().lower()
    out_value = int(programmatic_result.get('rounding_out_value', 0))

    if db_connected:
        # Check In Punch
        if in_value == expected_val:
            score += 20
            feedback_parts.append("DB: In-Punch value correct (5)")
        
        if in_method in ['2', 'nearest', 'round nearest']:
            score += 20
            feedback_parts.append("DB: In-Punch method correct (Nearest)")
            
        # Check Out Punch
        if out_value == expected_val:
            score += 20
            feedback_parts.append("DB: Out-Punch value correct (5)")
            
        if out_method in ['2', 'nearest', 'round nearest']:
            score += 20
            feedback_parts.append("DB: Out-Punch method correct (Nearest)")
    else:
        feedback_parts.append("DB verification skipped (connection failed). Relying on VLM.")

    # 2. VLM Verification (Trajectory Analysis)
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    prompt = """
    You are verifying an agent configuring 'Attendance Rounding' in AttendHRM software.
    
    Look for these specific actions in the screenshots:
    1. Navigation to 'Attendance' module or 'Rules'/'Settings'.
    2. A configuration screen showing 'Rounding' options.
    3. Setting 'In Punch' rounding to 'Nearest' and value '5'.
    4. Setting 'Out Punch' rounding to 'Nearest' and value '5'.
    
    Return JSON:
    {
        "settings_opened": boolean,
        "rounding_configured": boolean,
        "values_visible": boolean, 
        "correct_values_seen": boolean (5 minutes / Nearest),
        "save_action_observed": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('settings_opened'):
        score += 5
    if vlm_data.get('rounding_configured'):
        score += 5
    if vlm_data.get('correct_values_seen'):
        score += 10
        feedback_parts.append("VLM: Correct values (5 mins/Nearest) observed in UI")
        
        # Boost score if DB failed but VLM is very confident
        if not db_connected:
            score += 40 # Grant partial credit for DB portion based on visual evidence
            
    # Final sanity check
    app_running = programmatic_result.get('app_running', False)
    if not app_running:
        score = min(score, 50) # Penalty if app closed
        feedback_parts.append("App was not running at end")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }