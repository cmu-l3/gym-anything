#!/usr/bin/env python3
"""
Verifier for top_floor_thermal_mass_update task.

Checks:
1. Simulation ran during the session (timestamp check)
2. All 5 Top Floor spaces have FLOOR-WEIGHT set to 120 (tolerance ±5)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected path inside the container (Windows path mapped to generic location logic)
# In the setup/export scripts, we wrote to C:\Users\Docker\task_result.json
# The copy_from_env function handles the extraction.
RESULT_FILENAME = "task_result.json"
RESULT_PATH_WIN = "C:\\Users\\Docker\\task_result.json"

def verify_top_floor_thermal_mass_update(traj, env_info, task_info):
    """
    Verifies the eQUEST thermal mass update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_WIN, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task results. Ensure the export script ran successfully."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Scoring Criteria
    score = 0
    feedback_parts = []
    
    # Metadata targets
    target_val = 120
    tolerance = 5
    
    # Criterion 1: Simulation Ran (15 pts)
    sim_ran = result.get('sim_ran_during_task', False)
    if sim_ran:
        score += 15
        feedback_parts.append("Simulation ran successfully (+15)")
    else:
        feedback_parts.append("Simulation did NOT run during task (0/15)")

    # Criterion 2: Check Spaces (85 pts total, 17 pts per space)
    spaces_data = result.get('spaces', {})
    
    # Expected spaces based on 4StoreyBuilding model
    expected_spaces = ["T.South Perim Spc (T.S1)", "T.East Perim Spc (T.E2)", 
                       "T.North Perim Spc (T.N3)", "T.West Perim Spc (T.W4)", 
                       "T.Core Spc (T.C5)"]
    
    # Map common regex-matched names if slightly different in parsing
    # The export script uses exact names from INP.
    # We look for keys containing the cardinal directions if exact match fails
    
    correct_spaces_count = 0
    
    # Identify the 5 relevant T.* spaces found in the result
    t_spaces = {k: v for k, v in spaces_data.items() if k.startswith("T.")}
    
    if len(t_spaces) == 0:
        feedback_parts.append("No Top Floor spaces found in model data")
    
    for name, val in t_spaces.items():
        # Validate value
        try:
            val_float = float(val)
            if abs(val_float - target_val) <= tolerance:
                score += 17
                correct_spaces_count += 1
            elif val_float == -1:
                 # -1 indicates key not found in block
                 pass 
            else:
                # Wrong value
                pass
        except (ValueError, TypeError):
            pass

    if correct_spaces_count == 5:
        feedback_parts.append("All 5 Top Floor spaces updated correctly (+85)")
    elif correct_spaces_count > 0:
        feedback_parts.append(f"{correct_spaces_count}/5 Top Floor spaces updated correctly")
    else:
        feedback_parts.append("No spaces updated to correct FLOOR-WEIGHT")

    # Final Score Calc
    # Cap at 100
    score = min(score, 100)
    
    # Pass Condition: Score >= 60 AND Simulation Ran
    # We require simulation because it's part of the workflow goal
    passed = (score >= 60) and sim_ran
    
    if not sim_ran and score >= 60:
        feedback_parts.append("FAILED: Task requires running simulation to pass")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }