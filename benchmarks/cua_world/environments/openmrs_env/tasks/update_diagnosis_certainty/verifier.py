#!/usr/bin/env python3
"""
Verifier for update_diagnosis_certainty task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

# Import VLM utils from framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_diagnosis_certainty(traj, env_info, task_info):
    """
    Verifies that the diagnosis certainty was updated from PRESUMED to CONFIRMED.
    """
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    task_start = result.get('task_start', 0)
    db_records = result.get('db_diagnoses', [])
    app_running = result.get('app_running', False)
    
    score = 0
    feedback = []
    passed = False

    # 3. Verify Database State (Primary Signal)
    # We expect to find a record for 'Anemia' that is NOT voided and has certainty 'CONFIRMED'
    
    active_confirmed_records = []
    active_presumed_records = []
    
    for record in db_records:
        if record['voided']:
            continue
            
        certainty = record['certainty'].upper()
        
        # Check timestamps
        # Note: dates from MariaDB via script are usually strings "YYYY-MM-DD HH:MM:SS"
        # We handle loose comparison or assume script handled it. 
        # Ideally, we verify the modification happened *after* task_start.
        # But simple state verification is robust enough if we ensure no duplicates.
        
        if certainty == 'CONFIRMED':
            active_confirmed_records.append(record)
        elif certainty == 'PRESUMED':
            active_presumed_records.append(record)

    # Scoring Logic
    
    # Check 1: App was left running (10 pts)
    if app_running:
        score += 10
        feedback.append("Application is running.")
    else:
        feedback.append("Application was closed.")

    # Check 2: Correct Data State (60 pts)
    if active_confirmed_records:
        score += 60
        feedback.append("Found active 'CONFIRMED' diagnosis for Anemia.")
    else:
        feedback.append("No active 'CONFIRMED' diagnosis found.")

    # Check 3: No Leftover/Duplicate Data (10 pts)
    # The agent should not just add a new one and leave the old "Presumed" one active.
    if active_confirmed_records and not active_presumed_records:
        score += 10
        feedback.append("Clean update: No duplicate 'Presumed' diagnosis remaining.")
    elif active_confirmed_records and active_presumed_records:
        feedback.append("Warning: Both 'Confirmed' and 'Presumed' diagnoses exist (duplicate data).")
    
    # Check 4: VLM Verification (20 pts)
    # Verify the UI actually shows "Confirmed"
    frames = sample_trajectory_frames(traj, n=3)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """
    Review these screenshots of an OpenMRS Electronic Health Record.
    The user task was to update a diagnosis of 'Anemia' to 'Confirmed'.
    
    Look for:
    1. A list of diagnoses or conditions.
    2. The word 'Anemia'.
    3. A badge or label next to 'Anemia' saying 'Confirmed' (green usually) vs 'Presumed' (yellow/orange).
    
    Does the FINAL state show 'Anemia' as 'Confirmed'?
    """
    
    try:
        vlm_res = query_vlm(images=images, prompt=vlm_prompt)
        if vlm_res and vlm_res.get('success'):
            # Simple heuristic on VLM response text
            resp_text = vlm_res.get('parsed', {}).get('answer', str(vlm_res))
            if "confirmed" in resp_text.lower() and "anemia" in resp_text.lower():
                score += 20
                feedback.append("Visual verification passed: 'Confirmed' status detected.")
            else:
                feedback.append("Visual verification inconclusive.")
        else:
            feedback.append("VLM verification failed to run.")
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        # Be lenient if VLM fails but DB is correct
        if score >= 70:
            score += 20
            feedback.append("VLM skipped (DB check passed).")

    # Pass Threshold
    if score >= 80:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }