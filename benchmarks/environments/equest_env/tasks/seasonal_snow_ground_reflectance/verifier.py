#!/usr/bin/env python3
"""
Verifier for seasonal_snow_ground_reflectance task.

Requirements:
1. GROUND-REFLECTANCE must be an array of 12 monthly values.
2. Winter months (Jan, Feb, Dec) should be ~0.60.
3. Shoulder month (Mar) should be ~0.40.
4. Base months (Apr-Nov) should be ~0.20.
5. Simulation must have been run during the task session.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_JSON_PATH = "C:\\Users\\Docker\\task_result.json"
TARGET_WINTER = 0.60
TARGET_MARCH = 0.40
TARGET_BASE = 0.20
TOLERANCE = 0.02

def verify_seasonal_snow_ground_reflectance(traj, env_info, task_info):
    """
    Verify the ground reflectance values and simulation status.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_JSON_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to read task result file. Ensure the script finished successfully."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Simulation Status (15 pts)
    if result.get('sim_file_is_new', False):
        score += 15
        feedback_parts.append("Simulation run confirmed (+15)")
    elif result.get('sim_file_exists', False):
        feedback_parts.append("Simulation output exists but is old (task start > file mod time)")
    else:
        feedback_parts.append("No simulation output found")

    # 2. Check Reflectance Values (85 pts total)
    values = result.get('reflectance_values', [])
    
    # Validations
    if not isinstance(values, list) or len(values) < 12:
        feedback_parts.append(f"Invalid Ground Reflectance values found: {values}")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Helper for comparison
    def is_close(val, target):
        return abs(val - target) <= TOLERANCE

    # A. Winter Months: Jan(0), Feb(1), Dec(11) - 15 pts each (45 total)
    winter_indices = [0, 1, 11]
    winter_correct = 0
    for idx in winter_indices:
        if is_close(values[idx], TARGET_WINTER):
            winter_correct += 1
            score += 15
    
    if winter_correct == 3:
        feedback_parts.append("Winter months correct (+45)")
    else:
        feedback_parts.append(f"Winter months partial: {winter_correct}/3 correct")

    # B. March: Index 2 - 10 pts
    if is_close(values[2], TARGET_MARCH):
        score += 10
        feedback_parts.append("March value correct (+10)")
    else:
        feedback_parts.append(f"March value incorrect (got {values[2]}, expected {TARGET_MARCH})")

    # C. Base Months: Apr(3) to Nov(10) - 30 pts total (all or nothing block, or proportional)
    # Let's do proportional: 30 / 8 = 3.75 pts each
    base_indices = range(3, 11) # 3 to 10
    base_correct = 0
    for idx in base_indices:
        if is_close(values[idx], TARGET_BASE):
            base_correct += 1
            score += 3.75
    
    if base_correct == 8:
        feedback_parts.append("Summer/Fall months correct (+30)")
    else:
        feedback_parts.append(f"Summer/Fall months partial: {base_correct}/8 correct")

    # Round score
    score = int(round(score))
    
    # Pass threshold: 75 AND sim ran
    # If they got all winter months correct (45) + sim ran (15) + some others, they might pass.
    # The requirement is strictly "Winter months correct" for the logic below:
    
    passed = (score >= 75) and result.get('sim_file_is_new', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "values_found": values,
            "winter_correct": winter_correct,
            "march_correct": is_close(values[2], TARGET_MARCH),
            "base_correct": base_correct
        }
    }