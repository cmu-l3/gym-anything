#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lm317_design(traj, env_info, task_info):
    """
    Verifies the LM317 regulator design task.
    
    Criteria:
    1. Result file exists and was created during the task.
    2. Result file contains the correct R2 value (~1488 Ohms).
    3. VLM verifies the app was used correctly (LM317 calculator visible, correct inputs).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_r2 = metadata.get('expected_r2', 1488)
    tolerance = metadata.get('tolerance', 15) # Allow +/- 15 Ohms
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Timestamp (Anti-gaming)
    file_exists = result_data.get("file_exists", False)
    file_content = result_data.get("file_content", "").strip()
    task_start = result_data.get("task_start", 0)
    file_mod = result_data.get("file_mod_time", 0)
    
    if not file_exists:
        feedback.append("Result file '/sdcard/lm317_design.txt' not found.")
    else:
        score += 10
        if file_mod >= task_start:
            score += 10
            feedback.append("File created during task.")
        else:
            feedback.append("Warning: File timestamp predates task start.")

    # 3. Check Numeric Result
    value_correct = False
    parsed_value = None
    
    if file_content:
        # Extract number using regex (handles "R2=1488", "1488", "1488 Ohms")
        match = re.search(r'(\d+(\.\d+)?)', file_content)
        if match:
            try:
                parsed_value = float(match.group(1))
                # Check 1: Exact calculation (1488)
                if abs(parsed_value - expected_r2) <= tolerance:
                    score += 40
                    value_correct = True
                    feedback.append(f"Correct R2 value found: {parsed_value} (Expected ~{expected_r2})")
                # Check 2: Standard Resistor Value (1.5k = 1500)
                elif abs(parsed_value - 1500) <= 10:
                    score += 30 # Partial credit for standard value
                    value_correct = True
                    feedback.append(f"Standard resistor value found: {parsed_value} (Calculated was {expected_r2})")
                else:
                    feedback.append(f"Incorrect R2 value: {parsed_value} (Expected ~{expected_r2})")
            except ValueError:
                feedback.append(f"Could not parse number from: {file_content}")
        else:
            feedback.append("No numeric value found in file.")
    
    # 4. VLM Verification (Trajectory Analysis)
    # We check if the user actually used the LM317 calculator
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        frames.append(final_screen)
        
    vlm_prompt = f"""
    You are verifying an electrical engineering task on an Android app.
    The user should have:
    1. Opened an 'LM317' or 'Voltage Regulator' calculator.
    2. Entered '9' for Voltage/Vout and '240' for R1/Resistance.
    3. Calculated a result around 1488 Ohms (or 1.49 kOhms).
    
    Review the screenshots.
    - Did they reach a calculator screen? (Yes/No)
    - Can you see inputs 9 (Volts) and 240 (Ohms)? (Yes/No)
    - Is the result ~1488 visible? (Yes/No)
    
    Output JSON:
    {{
        "calculator_open": boolean,
        "inputs_visible": boolean,
        "result_visible": boolean,
        "explanation": "string"
    }}
    """
    
    vlm_result = query_vlm(frames, vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    if vlm_data.get("calculator_open"):
        score += 10
        feedback.append("VLM: Calculator accessed.")
    
    if vlm_data.get("inputs_visible"):
        score += 15
        feedback.append("VLM: Correct inputs (9V, 240R) detected.")
        
    if vlm_data.get("result_visible"):
        score += 15
        feedback.append("VLM: Result visible on screen.")
        
    # Final Pass Determination
    # Must have the correct value in file AND reasonable VLM evidence
    passed = (value_correct and score >= 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }