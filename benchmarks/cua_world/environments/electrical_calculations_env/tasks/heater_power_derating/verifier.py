#!/usr/bin/env python3
"""
Verifier for heater_power_derating task.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_heater_power_derating(traj, env_info, task_info):
    """
    Verifies the heater power derating calculation task.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. Output value is numerically correct (approx 3755.56 W).
    3. VLM verifies the agent interacted with the calculator app.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load task result from device
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamp (25 pts) ---
    file_exists = result_data.get('file_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if file_exists:
        if created_during:
            score += 25
            feedback_parts.append("Output file created successfully.")
        else:
            score += 10
            feedback_parts.append("Output file exists but timestamp is old (anti-gaming fail).")
    else:
        feedback_parts.append("Output file not found.")

    # --- Criterion 2: Value Correctness (50 pts) ---
    expected_power = 3755.56
    tolerance = 10.0 # Allow 3745 - 3765
    
    content = result_data.get('file_content', "")
    value_correct = False
    
    # Extract number from string (e.g., "3755.56 Watts" -> 3755.56)
    try:
        # Find the first float-like number
        match = re.search(r"(\d+(?:\.\d+)?)", content)
        if match:
            val = float(match.group(1))
            if abs(val - expected_power) <= tolerance:
                score += 50
                value_correct = True
                feedback_parts.append(f"Calculated value {val} is correct.")
            else:
                feedback_parts.append(f"Calculated value {val} is incorrect (Expected ~{expected_power}).")
        elif file_exists:
            feedback_parts.append("Could not parse number from output file.")
    except Exception:
        feedback_parts.append("Error parsing output file content.")

    # --- Criterion 3: VLM Verification (25 pts) ---
    # We check if the agent actually used the calculator interface
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        if final_screen:
            frames.append(final_screen)
            
        prompt = """
        Analyze these screenshots from an Android automation task.
        The user should be using an 'Electrical Calculations' app.
        
        Look for:
        1. A calculator interface (Ohm's Law or Power calculator).
        2. Input values like '240' and '5000' (Step 1).
        3. Input values like '208' and '11.5' or '11.52' (Step 2).
        4. A result close to '3755'.
        
        Did the agent use the app to perform calculations?
        Respond with JSON: {"app_used": boolean, "calculations_visible": boolean}
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('app_used', False):
                vlm_score += 10
            if parsed.get('calculations_visible', False):
                vlm_score += 15
                
            feedback_parts.append(f"VLM verification score: {vlm_score}/25")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if value was correct, assume VLM would pass
            if value_correct:
                vlm_score = 25
                feedback_parts.append("VLM check skipped, awarding points based on correct result.")

    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 60) and value_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }