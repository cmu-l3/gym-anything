#!/usr/bin/env python3
"""
Verifier for lighting_fixture_heat_fraction_update task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lighting_update(traj, env_info, task_info):
    """
    Verifies the eQUEST lighting update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task Metadata
    metadata = task_info.get('metadata', {})
    target_lpd = float(metadata.get('target_lpd', 0.72))
    target_return = float(metadata.get('target_return_air', 0.0))
    target_space = float(metadata.get('target_space_fraction', 1.0))
    target_spaces_list = metadata.get('target_spaces', ["M.S21", "M.E22", "M.N23", "M.W24", "M.C25"])

    # Load Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\lighting_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check Simulation
    sim_ran = result.get("sim_ran", False)
    if sim_ran:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10).")
    else:
        feedback_parts.append("Simulation did not run or was not saved after task start.")

    # Check Space Parameters
    spaces_data = result.get("spaces", {})
    
    # Points per parameter type
    points_per_space_param = 6 # 3 params * 5 spaces * 6 pts = 90 pts. Total 100 with sim.
    
    correct_lpd_count = 0
    correct_return_count = 0
    correct_space_count = 0
    
    for space_name in target_spaces_list:
        if space_name not in spaces_data:
            feedback_parts.append(f"Space {space_name} not found in project.")
            continue
            
        space_params = spaces_data[space_name]
        
        # Check LPD
        try:
            val = float(space_params.get("lpd", -1))
            if abs(val - target_lpd) < 0.01:
                score += points_per_space_param
                correct_lpd_count += 1
        except (ValueError, TypeError):
            pass

        # Check Return Air
        try:
            val = float(space_params.get("return_air", -1))
            if abs(val - target_return) < 0.01:
                score += points_per_space_param
                correct_return_count += 1
        except (ValueError, TypeError):
            pass
            
        # Check Space Fraction
        try:
            val = float(space_params.get("space_fraction", -1))
            if abs(val - target_space) < 0.01:
                score += points_per_space_param
                correct_space_count += 1
        except (ValueError, TypeError):
            pass

    # Summary Feedback
    if correct_lpd_count == 5:
        feedback_parts.append("All LPD values correct.")
    else:
        feedback_parts.append(f"LPD correct in {correct_lpd_count}/5 spaces.")
        
    if correct_return_count == 5:
        feedback_parts.append("All Return Air fractions correct.")
    else:
        feedback_parts.append(f"Return Air fraction correct in {correct_return_count}/5 spaces.")

    if correct_space_count == 5:
        feedback_parts.append("All Space fractions correct.")
    else:
        feedback_parts.append(f"Space fraction correct in {correct_space_count}/5 spaces.")

    # Pass Threshold
    # Must get at least 80 points.
    passed = score >= 80

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }