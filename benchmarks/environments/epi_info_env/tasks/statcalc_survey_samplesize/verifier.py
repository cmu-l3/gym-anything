#!/usr/bin/env python3
"""
Verifier for Epi Info 7 StatCalc Survey Sample Size task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_statcalc_survey_samplesize(traj, env_info, task_info):
    """
    Verifies that the agent calculated the correct sample sizes and saved them to a file.
    Uses multi-criteria scoring:
    1. File existence and anti-gaming (timestamps)
    2. Correct values for Survey A, B, and C
    3. VLM verification of StatCalc usage (trajectory)
    """
    
    # 1. Setup and retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {"Survey A": 196, "Survey B": 880, "Survey C": 1744})
    tolerance = metadata.get('tolerance', 10)

    # Copy result file from container (Windows path -> local temp)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Note: copy_from_env might need translation for Windows paths depending on the backend,
        # but usually the framework handles the container path string directly.
        copy_from_env(r"C:\tmp\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from container."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. File-based Verification (50 points)
    output_exists = result_data.get("output_exists", False)
    file_created_during_task = result_data.get("file_created_during_task", False)
    
    if not output_exists:
        feedback.append("Output file not found.")
    elif not file_created_during_task:
        feedback.append("Output file exists but was not created during the task (anti-gaming check failed).")
    else:
        score += 10
        feedback.append("Output file created successfully.")
        
        # Check values
        val_a = result_data.get("survey_a_val", 0)
        val_b = result_data.get("survey_b_val", 0)
        val_c = result_data.get("survey_c_val", 0)
        
        # Survey A
        if abs(val_a - expected_values["Survey A"]) <= tolerance:
            score += 10
            feedback.append(f"Survey A correct ({val_a}).")
        else:
            feedback.append(f"Survey A incorrect (Expected ~{expected_values['Survey A']}, Got {val_a}).")
            
        # Survey B
        if abs(val_b - expected_values["Survey B"]) <= tolerance:
            score += 10
            feedback.append(f"Survey B correct ({val_b}).")
        else:
            feedback.append(f"Survey B incorrect (Expected ~{expected_values['Survey B']}, Got {val_b}).")
            
        # Survey C (Higher weight or equal?) Keeping equal for simplicity, maybe bonus for complex one
        if abs(val_c - expected_values["Survey C"]) <= tolerance:
            score += 20
            feedback.append(f"Survey C correct ({val_c}).")
        else:
            feedback.append(f"Survey C incorrect (Expected ~{expected_values['Survey C']}, Got {val_c}).")

    # 3. VLM Trajectory Verification (50 points)
    # Check if StatCalc was actually used
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent's work in Epi Info 7 StatCalc.
    The agent should have:
    1. Opened the 'StatCalc' module (look for a window titled StatCalc or a calculator interface).
    2. Selected 'Population Survey' or 'Sample Size'.
    3. Entered numbers into fields like 'Population Size', 'Expected Frequency', 'Confidence Limits'.
    
    Review these screenshots.
    - Do you see the StatCalc interface?
    - Do you see numbers being entered into sample size calculation fields?
    - Does it look like the agent performed the calculations inside the software?
    
    Respond in JSON:
    {
        "statcalc_visible": boolean,
        "inputs_visible": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("statcalc_visible"):
            score += 25
            feedback.append("VLM: StatCalc interface detected.")
            if parsed.get("inputs_visible"):
                score += 25
                feedback.append("VLM: Data entry detected.")
            else:
                feedback.append("VLM: StatCalc open but data entry unclear.")
        else:
            feedback.append("VLM: StatCalc interface NOT detected in trajectory.")
    else:
        # Fallback if VLM fails - give partial credit if numbers are correct (benefit of doubt)
        if score >= 40: # If they got numbers right
            score += 20
            feedback.append("VLM check skipped/failed, partial points awarded based on correct output.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }