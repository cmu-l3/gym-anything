#!/usr/bin/env python3
import json
import re
import os
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_zener_design(traj, env_info, task_info):
    """
    Verifies the Zener Diode Regulator Design task.
    
    Criteria:
    1. Output file exists and was created during the task.
    2. Resistor value is within tolerance (Target: 228 Ohms).
    3. Power value is within tolerance (Target: 142.5 mW).
    4. Anti-gaming: Ensures values aren't from the wrong calculation (e.g. ignoring bias).
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_r = metadata.get('expected_resistor_ohms', 228)
    expected_p = metadata.get('expected_power_mw', 142.5)
    tol_r = metadata.get('tolerance_resistor', 5)
    tol_p = metadata.get('tolerance_power', 10)
    
    # Retrieve result JSON from device
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/tasks/zener_design/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Evaluate File Existence & Timing (20 points)
    score = 0
    feedback = []
    
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Result file not found at /sdcard/tasks/zener_design/result.txt"}
    
    if not result_data.get('created_during_task'):
        feedback.append("Warning: Result file timestamp suggests it wasn't created during this session.")
        # We penalize but don't fail immediately if content is correct, but for strict anti-gaming this is 0.
        # Let's deduct points.
    else:
        score += 20
        feedback.append("File created successfully.")

    # 3. Parse Content (80 points total)
    content = result_data.get('file_content', '')
    logger.info(f"File content: {content}")

    # Regex to find numbers associated with "Resistor" and "Power"
    # Handles: "Resistor: 228 Ohms", "R: 228", "228 ohm", etc.
    r_match = re.search(r'(?:Resistor|R)[^0-9]*([0-9.]+)', content, re.IGNORECASE)
    p_match = re.search(r'(?:Power|P)[^0-9]*([0-9.]+)', content, re.IGNORECASE)

    # Validate Resistor (40 points)
    r_val = float(r_match.group(1)) if r_match else None
    
    if r_val is not None:
        if abs(r_val - expected_r) <= tol_r:
            score += 40
            feedback.append(f"Resistor value correct ({r_val} Ohms).")
        elif abs(r_val - 285) <= tol_r:
            feedback.append(f"Resistor value incorrect ({r_val} Ohms). You likely forgot the Zener bias current (5mA).")
        else:
            feedback.append(f"Resistor value incorrect. Expected ~{expected_r}, got {r_val}.")
    else:
        feedback.append("Could not parse Resistor value from file.")

    # Validate Power (40 points)
    p_val = float(p_match.group(1)) if p_match else None
    
    if p_val is not None:
        # Check mW match
        if abs(p_val - expected_p) <= tol_p:
            score += 40
            feedback.append(f"Power value correct ({p_val} mW).")
        # Check Watts match (e.g., 0.14 W)
        elif abs(p_val - (expected_p/1000.0)) <= (tol_p/1000.0):
            score += 40
            feedback.append(f"Power value correct ({p_val} W).")
        else:
            feedback.append(f"Power value incorrect. Expected ~{expected_p} mW, got {p_val}.")
    else:
        feedback.append("Could not parse Power value from file.")

    # 4. Final Verdict
    passed = score >= 80  # Must get both values mostly right + file creation
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }