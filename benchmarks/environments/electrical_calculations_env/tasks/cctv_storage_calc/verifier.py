#!/usr/bin/env python3
"""
Verifier for cctv_storage_calc task.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cctv_storage(traj, env_info, task_info):
    """
    Verifies the CCTV storage calculation task.
    
    Criteria:
    1. Result file exists and contains a number in valid range (GB).
    2. VLM confirms:
       - Correct calculator (CCTV/Harddrive) is open.
       - Inputs are correct (6 cams, 1080p, 15fps, H.264, 14 days).
       - App is visible in final state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_range = metadata.get('expected_range_gb', [1500, 3500])
    
    score = 0
    feedback_parts = []
    
    # 1. Analyze programmatic result (File content)
    # ---------------------------------------------
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        feedback_parts.append("Failed to retrieve task status")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result_data.get('file_exists', False)
    content_raw = result_data.get('file_content', "").strip()
    
    val_gb = 0.0
    valid_number = False
    
    if file_exists:
        # Extract number from string (e.g. "2200", "2200 GB", "2.2 TB")
        # Agent was asked for GB, but might write TB.
        # Simple regex for the first float found
        match = re.search(r"([0-9]*\.?[0-9]+)", content_raw)
        if match:
            val_gb = float(match.group(1))
            valid_number = True
            
            # Heuristic: if value is < 10, they probably wrote TB (e.g. 2.2)
            if val_gb < 100: 
                val_gb *= 1000  # Convert to GB
                feedback_parts.append(f"Interpreted value as TB, converted to {val_gb} GB")
            
            if expected_range[0] <= val_gb <= expected_range[1]:
                score += 40
                feedback_parts.append(f"Reported value {val_gb} GB is within valid range")
            else:
                feedback_parts.append(f"Reported value {val_gb} GB is outside expected range ({expected_range})")
        else:
            feedback_parts.append("File exists but contains no valid number")
    else:
        feedback_parts.append("Result file not created")

    # 2. VLM Verification (Trajectory & Final State)
    # ----------------------------------------------
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # We use the final screen for detailed input check
    vlm_prompt = """
    Analyze this screenshot from the 'Electrical Engineering Calculations' Android app.
    
    Check for the 'CCTV' or 'Harddrive/Storage' calculator.
    Verify these inputs:
    1. Number of cameras: 6
    2. Resolution: 1080p (or 1920x1080)
    3. Frame Rate: 15 fps
    4. Compression: H.264
    5. Days/Period: 14
    
    Does the screen show a calculated result (Storage/Disk Space)?
    
    Return JSON:
    {
        "calculator_open": boolean,
        "inputs_correct": boolean,
        "result_visible": boolean,
        "feedback": "string"
    }
    """
    
    vlm_res = query_vlm(prompt=vlm_prompt, image=final_screen)
    
    vlm_score = 0
    if vlm_res.get('success'):
        parsed = vlm_res.get('parsed', {})
        if parsed.get('calculator_open'):
            vlm_score += 20
            feedback_parts.append("Correct calculator open")
        else:
            feedback_parts.append("Wrong calculator or app not open")
            
        if parsed.get('inputs_correct'):
            vlm_score += 20
            feedback_parts.append("Inputs configured correctly")
        else:
            feedback_parts.append("Inputs incorrect or not visible")
            
        if parsed.get('result_visible'):
            vlm_score += 20
            feedback_parts.append("Calculation result visible")
            
        score += vlm_score
    else:
        feedback_parts.append("VLM verification failed")

    # Final Pass/Fail
    # Need at least 80 points (must have result file + correct inputs)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }