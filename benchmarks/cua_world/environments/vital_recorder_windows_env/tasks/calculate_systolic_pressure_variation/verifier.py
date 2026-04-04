#!/usr/bin/env python3
"""
Verifier for calculate_systolic_pressure_variation task.

Verification Logic:
1. File Existence: Report txt and waveform png must exist.
2. Anti-Gaming: Files must be created during task execution.
3. Content Validity:
   - Report must contain Max, Min, SPV values.
   - Math Check: SPV == Max - Min (within tolerance).
   - Plausibility Check: SBP values within physiological range (60-200).
4. VLM Verification:
   - Check if agent navigated to waveform view.
   - Check if correct track (ART) is visible.
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spv_calculation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check Report File (30 points)
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 15
        feedback.append("Report file created successfully.")
        
        # Check parsed values
        p_max = result.get('parsed_max', 0)
        p_min = result.get('parsed_min', 0)
        p_spv = result.get('parsed_spv', 0)
        
        # Plausibility Check (15 points)
        if 60 < p_max < 220 and 30 < p_min < 180 and p_max > p_min:
            score += 10
            feedback.append(f"Values are physiologically plausible (Max: {p_max}, Min: {p_min}).")
            
            # Math Consistency Check
            if abs(p_spv - (p_max - p_min)) < 1.0:
                score += 5
                feedback.append("SPV calculation is mathematically correct.")
            else:
                feedback.append(f"SPV math error: {p_max} - {p_min} != {p_spv}")
        else:
            feedback.append("Reported values are implausible or zero.")
    else:
        feedback.append("Report file missing or not created during task.")

    # 3. Check Screenshot File (20 points)
    if result.get('image_exists') and result.get('image_created_during_task'):
        if result.get('image_size_bytes', 0) > 5000: # Min 5KB
            score += 20
            feedback.append("Waveform screenshot saved.")
        else:
            feedback.append("Waveform screenshot file is empty or too small.")
    else:
        feedback.append("Waveform screenshot missing.")

    # 4. VLM Verification (50 points)
    # We verify that the agent actually interacted with the waveform
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        Review these screenshots of the Vital Recorder software.
        1. Is an arterial blood pressure waveform visible (usually red)?
        2. Does the view show a zoomed-in waveform or a cursor checking specific values?
        3. Is there evidence of measurement (crosshairs, tooltips with numbers)?
        
        Task: The user should be measuring peak systolic pressure.
        """
        
        vlm_response = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_response.get('success'):
            analysis = vlm_response.get('result', '').lower()
            if "waveform" in analysis or "red" in analysis:
                score += 25
                feedback.append("VLM confirms waveform visibility.")
            
            if "cursor" in analysis or "crosshair" in analysis or "measurement" in analysis or "zoom" in analysis:
                score += 25
                feedback.append("VLM confirms interaction/measurement activity.")
            else:
                feedback.append("VLM did not clearly see cursor interaction.")
        else:
            feedback.append("VLM verification failed to run.")
            # Fallback points if files are perfect
            if score >= 50:
                score += 10 

    # 5. Final Pass/Fail
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }