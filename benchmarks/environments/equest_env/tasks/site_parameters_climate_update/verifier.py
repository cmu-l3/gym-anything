#!/usr/bin/env python3
"""
Verifier for site_parameters_climate_update task.

The agent must:
1. Update SITE-PARAMETERS: ALTITUDE=285, C-STATE=24
2. Update BUILD-PARAMETERS: GROUND-T=(48, 50, 55, 62, 70, 77, 81, 81, 75, 65, 55, 49)
3. Run Simulation (generating a new .SIM file)
4. Save Project (updating .inp file)

Scoring (100 pts total):
- Simulation ran during session: 10 pts
- ALTITUDE correct (±5): 10 pts
- C-STATE correct (24): 5 pts
- GROUND-T values correct (±1): 5 pts each * 12 months = 60 pts
- Project saved: 15 pts

Pass Threshold: Score >= 60 AND Simulation Ran AND at least 8/12 Ground Temps correct.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# This path matches where export_result.ps1 saves the file inside the container
RESULT_PATH_IN_CONTAINER = "C:\\Users\\Docker\\site_params_result.json"

TARGET_GROUND_T = [48, 50, 55, 62, 70, 77, 81, 81, 75, 65, 55, 49]

def verify_site_parameters_climate_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_IN_CONTAINER, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy or parse result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data. Did you save the project and run the simulation?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify Simulation Run (10 pts)
    sim_ran = result.get('sim_file_is_new', False)
    if sim_ran:
        score += 10
        feedback.append("Simulation run detected (+10)")
    else:
        feedback.append("Simulation NOT run or results not saved.")

    # 3. Verify Project Save (15 pts)
    # If sim ran, project might not be saved, but usually Sim saves temp files. 
    # We specifically check if the .INP was updated.
    if result.get('inp_file_modified', False):
        score += 15
        feedback.append("Project file saved (+15)")
    else:
        feedback.append("Project file (.INP) not saved.")

    # 4. Verify Altitude (10 pts)
    try:
        alt = int(result.get('altitude', -1))
        if 280 <= alt <= 290:
            score += 10
            feedback.append(f"Altitude correct ({alt}) (+10)")
        else:
            feedback.append(f"Altitude incorrect: found {alt}, expected 285")
    except (ValueError, TypeError):
        feedback.append("Altitude value unreadable")

    # 5. Verify State (5 pts)
    try:
        state = int(result.get('c_state', -1))
        if state == 24:
            score += 5
            feedback.append("State code correct (+5)")
        else:
            feedback.append(f"State code incorrect: found {state}, expected 24")
    except (ValueError, TypeError):
        feedback.append("State code unreadable")

    # 6. Verify Ground Temps (60 pts total, 5 pts each)
    found_temps = result.get('ground_t', [])
    # Handle case where list might be strings
    try:
        found_temps = [float(x) for x in found_temps]
    except:
        found_temps = []

    correct_temps_count = 0
    
    if len(found_temps) == 12:
        for i, target in enumerate(TARGET_GROUND_T):
            # Tolerance ±1 degree
            if abs(found_temps[i] - target) <= 1.0:
                score += 5
                correct_temps_count += 1
            else:
                pass # Silent fail for individual months to reduce log noise
        
        feedback.append(f"Ground Temperatures: {correct_temps_count}/12 correct (+{correct_temps_count * 5})")
    else:
        feedback.append(f"Ground Temperatures: Found {len(found_temps)} values, expected 12.")

    # 7. Final Assessment
    # Pass threshold: Score >= 60 AND Simulation Ran AND at least 8 temps correct
    passed = (score >= 60) and sim_ran and (correct_temps_count >= 8)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }