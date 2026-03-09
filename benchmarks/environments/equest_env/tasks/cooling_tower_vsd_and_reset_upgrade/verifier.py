#!/usr/bin/env python3
"""
Verifier for cooling_tower_vsd_and_reset_upgrade task.

Task Requirements:
1. Condenser Water Loop: COOL-SETPT-CTRL = WET-BULB-RESET
2. Cooling Tower: FAN-CONTROL = SPEED-CONTROL
3. Cooling Tower: MIN-FAN-SPEED = 0.2
4. Simulation must be run (SIM file modified after task start)

Scoring:
- Simulation Ran: 10 pts
- Loop Control Correct: 30 pts
- Fan Control Correct: 30 pts
- Min Speed Correct: 30 pts

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
EXPECTED_LOOP_CONTROL = "WET-BULB-RESET"
EXPECTED_FAN_CONTROL = "SPEED-CONTROL"
EXPECTED_MIN_SPEED = 0.2
TOLERANCE = 0.01

def verify_cooling_tower_vsd_and_reset_upgrade(traj, env_info, task_info):
    """
    Verify the eQUEST cooling tower upgrade task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    result_remote_path = "C:\\Users\\Docker\\task_result.json"
    
    # Create temp file for result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result.close()
    
    try:
        # Copy result from environment
        copy_from_env(result_remote_path, temp_result.name)
        
        # Read JSON
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
            
    except Exception as e:
        logger.error(f"Failed to copy or read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data."}
    finally:
        if os.path.exists(temp_result.name):
            os.remove(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Run (10 pts)
    if data.get("sim_file_is_new", False):
        score += 10
        feedback_parts.append("Simulation run confirmed (+10).")
    elif data.get("sim_file_exists", False):
        feedback_parts.append("Simulation output exists but is old (did not run during task).")
    else:
        feedback_parts.append("Simulation output not found.")

    # 2. Verify Loop Control (30 pts)
    actual_loop = data.get("loop_control", "UNKNOWN")
    if actual_loop == EXPECTED_LOOP_CONTROL:
        score += 30
        feedback_parts.append(f"CW Loop control correctly set to {EXPECTED_LOOP_CONTROL} (+30).")
    else:
        feedback_parts.append(f"CW Loop control incorrect. Expected: {EXPECTED_LOOP_CONTROL}, Found: {actual_loop}.")

    # 3. Verify Fan Control (30 pts)
    actual_fan = data.get("fan_control", "UNKNOWN")
    if actual_fan == EXPECTED_FAN_CONTROL:
        score += 30
        feedback_parts.append(f"Tower Fan control correctly set to {EXPECTED_FAN_CONTROL} (+30).")
    else:
        feedback_parts.append(f"Tower Fan control incorrect. Expected: {EXPECTED_FAN_CONTROL}, Found: {actual_fan}.")

    # 4. Verify Min Fan Speed (30 pts)
    try:
        actual_speed = float(data.get("min_fan_speed", -1))
        if abs(actual_speed - EXPECTED_MIN_SPEED) <= TOLERANCE:
            score += 30
            feedback_parts.append(f"Tower Min Speed correctly set to {actual_speed} (+30).")
        else:
            feedback_parts.append(f"Tower Min Speed incorrect. Expected: {EXPECTED_MIN_SPEED}, Found: {actual_speed}.")
    except (ValueError, TypeError):
        feedback_parts.append("Tower Min Speed value could not be parsed.")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }