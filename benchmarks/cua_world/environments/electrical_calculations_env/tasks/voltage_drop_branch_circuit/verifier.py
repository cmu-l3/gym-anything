#!/usr/bin/env python3
"""
Verifier for Voltage Drop Branch Circuit task.

Criteria:
1. Result file exists and was created during the task.
2. File content parses correctly and matches input parameters.
3. Calculated voltage drop is within physically valid range (3.5V - 7.0V).
4. VLM verification confirms app usage and correct calculator screen.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_voltage_drop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timestamp (20 pts)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Result file /sdcard/voltage_drop_result.txt not found."}
    
    if not result.get('file_created_during_task', False):
        feedback_parts.append("File exists but was not created during this task session.")
        # Continue but with penalty
    else:
        score += 20
        feedback_parts.append("Result file created successfully.")

    # 2. Content Analysis (40 pts)
    content = result.get('file_content', '').replace('\\n', '\n')
    
    # Parse key-value pairs
    data = {}
    for line in content.split('\n'):
        if ':' in line:
            key, val = line.split(':', 1)
            data[key.strip()] = val.strip()

    # Check Inputs
    required_inputs = {
        "Voltage": "120",
        "Current": "20",
        "Wire Gauge": "12", 
        "Length": "75"
    }
    
    inputs_correct = True
    for key, expected_partial in required_inputs.items():
        val = data.get(key, "")
        if expected_partial not in val: # Simple substring check (e.g. "12" in "12 AWG")
            inputs_correct = False
            feedback_parts.append(f"Incorrect/Missing {key}: expected {expected_partial}, got '{val}'")
    
    if inputs_correct:
        score += 15
        feedback_parts.append("Input parameters correctly recorded.")

    # Check Outputs
    vd_val = 0.0
    try:
        vd_str = data.get("Voltage Drop", "0").split()[0] # Get number before 'V'
        vd_val = float(vd_str)
        
        # Range check: 3.5V to 7.0V covers standard calculation variations
        if 3.5 <= vd_val <= 7.0:
            score += 25
            feedback_parts.append(f"Calculated Voltage Drop ({vd_val} V) is within valid range.")
        else:
            feedback_parts.append(f"Calculated Voltage Drop ({vd_val} V) is outside expected range (3.5-7.0 V).")
    except ValueError:
        feedback_parts.append("Could not parse Voltage Drop value.")

    # 3. VLM Verification (40 pts)
    # Check if they actually used the app or just wrote the file
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Review these screenshots of an Android task. The user is supposed to:
    1. Open 'Electrical Engineering Calculations' app.
    2. Go to the 'Voltage Drop' calculator.
    3. Enter values: 120V, 20A, 12 AWG, 75 ft.
    4. See a result.

    Answer JSON:
    {
        "app_opened": boolean,
        "calculator_seen": boolean,
        "values_entered": boolean, 
        "confidence": "low|medium|high"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('app_opened', False):
        score += 10
    if vlm_data.get('calculator_seen', False):
        score += 15
    if vlm_data.get('values_entered', False):
        score += 15
        
    if score < 40 and vlm_data.get('confidence') == 'high':
        feedback_parts.append("VLM did not observe correct app usage.")

    final_passed = score >= 60 and result.get('file_created_during_task', False)
    
    return {
        "passed": final_passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }