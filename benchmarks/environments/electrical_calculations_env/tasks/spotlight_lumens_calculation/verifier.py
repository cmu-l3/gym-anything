#!/usr/bin/env python3
"""
Verifier for Spotlight Lumens Calculation Task.

Logic:
1. Retrieval: Pulls /sdcard/task_result.json and screenshots from the Android environment.
2. Programmatic Check:
   - Parses the output file content for a numerical value.
   - Verifies the value against the physical formula: Φ = 2πI(1 - cos(θ/2)).
   - Checks file creation timestamps to prevent "do nothing" or pre-caching gaming.
3. VLM Verification:
   - Analyzes trajectory frames to confirm the agent navigated to "Lighting" > "Lumens - Candela".
   - Confirms the agent entered the specific values (12000, 40).

Scoring:
- 20 pts: Result file created during task window.
- 40 pts: Correct calculation result (within tolerance).
- 40 pts: VLM confirmation of correct workflow (navigation + inputs).
"""

import json
import os
import math
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spotlight_lumens(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # --- 1. Retrieve Data from Environment ---
    temp_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/sdcard/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_json_path):
            os.remove(temp_json_path)

    # --- 2. Programmatic Verification (60 points) ---
    score = 0
    feedback = []
    
    # Criterion A: File Creation (20 pts)
    file_exists = result_data.get("file_exists", False)
    task_start = result_data.get("task_start", 0)
    file_mtime = result_data.get("file_mtime", 0)
    
    if file_exists and file_mtime > task_start:
        score += 20
        feedback.append("Result file created successfully.")
    else:
        feedback.append("Result file missing or not created during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion B: Value Correctness (40 pts)
    content = result_data.get("file_content", "")
    
    # Extract number from string like "Lumens: 4547.7"
    import re
    numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
    
    if not numbers:
        feedback.append(f"Could not parse number from file content: '{content}'")
    else:
        # Take the last number found, assuming it's the result
        agent_value = float(numbers[-1])
        
        # Ground Truth Calculation
        # I = 12000 cd, theta = 40 deg
        I = 12000
        theta_deg = 40
        theta_rad = math.radians(theta_deg)
        # Formula: Phi = 2 * pi * I * (1 - cos(theta/2))
        expected_lumens = 2 * math.pi * I * (1 - math.cos(theta_rad / 2))
        
        # Tolerance (±5%)
        lower_bound = expected_lumens * 0.95
        upper_bound = expected_lumens * 1.05
        
        if lower_bound <= agent_value <= upper_bound:
            score += 40
            feedback.append(f"Value {agent_value:.2f} lm is correct (Expected ~{expected_lumens:.2f}).")
        else:
            feedback.append(f"Value {agent_value:.2f} lm is incorrect (Expected ~{expected_lumens:.2f}).")

    # --- 3. VLM Verification (40 points) ---
    # We check if the agent actually used the app features
    frames = sample_trajectory_frames(traj, n=4)
    
    prompt = """
    You are verifying an electrical engineering task on an Android app.
    The user must calculate Luminous Flux for a spotlight.
    
    Check these screenshots for the following evidence:
    1. Did the user navigate to a "Lighting" or "Lumens - Candela" calculator?
    2. Did the user enter '12000' (or '12,000') in an input field?
    3. Did the user enter '40' in an input field?
    
    Return JSON:
    {
      "calculator_visible": boolean,
      "inputs_visible": boolean,
      "explanation": "string"
    }
    """
    
    try:
        query_func = env_info.get('query_vlm')
        if query_func:
            vlm_response = query_func(images=frames, prompt=prompt)
            vlm_data = vlm_response.get('parsed', {})
            
            if vlm_data.get("calculator_visible"):
                score += 20
                feedback.append("VLM confirmed correct calculator usage.")
            else:
                feedback.append("VLM could not confirm calculator navigation.")
                
            if vlm_data.get("inputs_visible"):
                score += 20
                feedback.append("VLM confirmed correct input values.")
            else:
                feedback.append("VLM could not confirm input values 12000/40.")
        else:
            # Fallback if VLM not available but value is correct: give partial credit
            feedback.append("VLM not available; skipping workflow verification.")
            if score >= 60: 
                score += 20 # Benevolent fallback
            
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback.append("VLM verification error.")

    # --- Final Decision ---
    # Must have the correct value (programmatic) to pass
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }