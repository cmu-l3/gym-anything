#!/usr/bin/env python3
"""
Verifier for top_floor_occupancy_retrofit task.

The agent must:
1. Update occupancy parameters for all 5 Top Floor (T.*) spaces:
   - AREA/PERSON: 75 (±2.0)
   - PEOPLE-HG-SENS: 275 (±5.0)
   - PEOPLE-HG-LAT: 225 (±5.0)
2. Run simulation (SIM file modified > task start).

Scoring (100 pts total):
- Simulation ran: 10 pts
- Per space (5 spaces total):
  - AREA/PERSON correct: 6 pts (Max 30)
  - SENS correct: 6 pts (Max 30)
  - LAT correct: 6 pts (Max 30)

Pass Threshold: 60 pts AND Simulation ran AND at least 3 spaces have correct AREA/PERSON.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\top_floor_occupancy_retrofit_result.json"
TARGET_SPACES = ["T.S31", "T.E32", "T.N33", "T.W34", "T.C35"]

# Targets & Tolerances
TARGET_AREA = 75.0
TOL_AREA = 2.0
TARGET_SENS = 275.0
TOL_SENS = 5.0
TARGET_LAT = 225.0
TOL_LAT = 5.0

def verify_top_floor_occupancy_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result file."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Run (10 pts)
    sim_ran = result.get('sim_file_is_new', False)
    if sim_ran:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation NOT run (or not saved)")

    # 2. Verify Space Parameters (90 pts distributed)
    spaces_data = result.get('spaces', {})
    
    correct_area_count = 0
    correct_sens_count = 0
    correct_lat_count = 0
    
    # Check all expected spaces are present
    found_spaces = 0
    
    for space_name in TARGET_SPACES:
        if space_name not in spaces_data:
            feedback_parts.append(f"Space {space_name} not found")
            continue
            
        found_spaces += 1
        data = spaces_data[space_name]
        
        # Check AREA/PERSON (6 pts)
        val_area = data.get('area_per_person', -1)
        if abs(val_area - TARGET_AREA) <= TOL_AREA:
            score += 6
            correct_area_count += 1
            
        # Check SENS (6 pts)
        val_sens = data.get('people_hg_sens', -1)
        if abs(val_sens - TARGET_SENS) <= TOL_SENS:
            score += 6
            correct_sens_count += 1
            
        # Check LAT (6 pts)
        val_lat = data.get('people_hg_lat', -1)
        if abs(val_lat - TARGET_LAT) <= TOL_LAT:
            score += 6
            correct_lat_count += 1

    # Feedback summary
    feedback_parts.append(f"Area/Person corrected: {correct_area_count}/5")
    feedback_parts.append(f"Sensible HG corrected: {correct_sens_count}/5")
    feedback_parts.append(f"Latent HG corrected: {correct_lat_count}/5")

    # Pass Condition
    # >= 60 points total
    # Simulation must have run
    # At least 3/5 spaces must have density updated (core requirement)
    passed = (score >= 60) and sim_ran and (correct_area_count >= 3)
    
    if not passed:
        if not sim_ran:
            feedback_parts.append("FAIL: Simulation required")
        if correct_area_count < 3:
            feedback_parts.append("FAIL: Occupancy density not updated on enough spaces")
            
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }