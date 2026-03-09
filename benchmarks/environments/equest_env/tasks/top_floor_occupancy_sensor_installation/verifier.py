#!/usr/bin/env python3
"""
Verifier for top_floor_occupancy_sensor_installation task.

The agent must:
1. Enable Occupancy Sensor control for 5 Top Floor spaces.
2. Set Area Fitted to 90% (0.9).
3. Run Simulation (generate fresh .SIM file).

Scoring:
- Simulation run: 10 pts
- Per zone (5 zones):
    - Correct Type (OCCUPANCY-SENSOR): 9 pts
    - Correct Prob (0.9): 9 pts
Total: 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# This matches the path in export_result.ps1
RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

TARGET_SPACES = ["T.S31", "T.E32", "T.N33", "T.W34", "T.C35"]
EXPECTED_TYPE = "OCCUPANCY-SENSOR"
EXPECTED_PROB = 0.9
PROB_TOLERANCE = 0.01

def verify_top_floor_occupancy_sensor_installation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to read task result file. Did the agent save the project?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Run (10 pts)
    if result.get("sim_file_is_new", False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10).")
    else:
        feedback_parts.append("Simulation was NOT run during the task (0/10).")

    # 2. Verify Spaces (90 pts total)
    spaces_data = result.get("spaces", {})
    
    spaces_correct_count = 0
    
    for space_name in TARGET_SPACES:
        space_score = 0
        data = spaces_data.get(space_name, {})
        
        # Check Type
        actual_type = data.get("type", "NONE")
        if actual_type == EXPECTED_TYPE:
            space_score += 9
        
        # Check Prob
        actual_prob = data.get("prob", 0.0)
        if abs(actual_prob - EXPECTED_PROB) <= PROB_TOLERANCE:
            space_score += 9
            
        score += space_score
        
        if space_score == 18:
            spaces_correct_count += 1
        elif space_score > 0:
            feedback_parts.append(f"{space_name}: Partial ({actual_type}, {actual_prob})")
        else:
            feedback_parts.append(f"{space_name}: Incorrect")

    feedback_parts.append(f"Spaces fully correct: {spaces_correct_count}/5")

    # Final Pass Check
    # Need at least 64 points (Sim + 3 zones fully correct)
    passed = (score >= 64) and result.get("sim_file_is_new", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }