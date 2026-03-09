#!/usr/bin/env python3
"""
Verifier for top_floor_vav_retrofit task.

The agent must:
1. Convert 5 Top Floor systems (T.*) to PVAVS.
2. Set FAN-CONTROL = SPEED.
3. Set COOL-CONTROL = WARMEST.
4. Set MAX-SUPPLY-T = 65.
5. Run Simulation.

Scoring:
- Simulation Ran: 10 pts
- Per system (5 systems):
  - Type (PVAVS): 5 pts
  - Fan (SPEED): 5 pts
  - Cool (WARMEST): 5 pts
  - Max Sup (65): 3 pts
  Total per system: 18 pts
  Total for 5 systems: 90 pts
Total Max Score: 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the container (Windows path mapped)
# Note: In the python verifier running on host, we use copy_from_env to get this file.
RESULT_PATH = "C:\\Users\\Docker\\top_floor_vav_retrofit_result.json"

TARGET_SYSTEMS = ["T.S31", "T.E32", "T.N33", "T.W34", "T.C35"]

def verify_top_floor_vav_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results. Ensure project was saved and simulation run. Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Simulation Run (10 pts)
    sim_ran = result.get('sim_file_new', False)
    if sim_ran:
        score += 10
        feedback.append("Simulation run confirmed (+10).")
    elif result.get('sim_file_exists', False):
        feedback.append("Simulation output exists but is old (not run during task).")
    else:
        feedback.append("No simulation output found.")

    # 2. Verify System Parameters (90 pts distributed)
    systems_data = result.get('systems', {})
    
    systems_passed_count = 0
    
    for sys_name in TARGET_SYSTEMS:
        sys_data = systems_data.get(sys_name, {})
        sys_score = 0
        sys_feedback = []
        
        # Check SYSTEM-TYPE (5 pts)
        val_type = sys_data.get('SYSTEM-TYPE', 'UNKNOWN')
        if val_type == 'PVAVS':
            sys_score += 5
        else:
            sys_feedback.append(f"Type: {val_type}!=PVAVS")

        # Check FAN-CONTROL (5 pts)
        val_fan = sys_data.get('FAN-CONTROL', 'UNKNOWN')
        if val_fan == 'SPEED':
            sys_score += 5
        else:
            sys_feedback.append(f"Fan: {val_fan}!=SPEED")

        # Check COOL-CONTROL (5 pts)
        val_cool = sys_data.get('COOL-CONTROL', 'UNKNOWN')
        if val_cool == 'WARMEST':
            sys_score += 5
        else:
            sys_feedback.append(f"CoolCtrl: {val_cool}!=WARMEST")

        # Check MAX-SUPPLY-T (3 pts)
        # Allow small float tolerance if parsed as number, string comparison if exact
        val_temp_raw = sys_data.get('MAX-SUPPLY-T', '0')
        try:
            val_temp = float(val_temp_raw)
            if abs(val_temp - 65.0) < 0.5:
                sys_score += 3
            else:
                sys_feedback.append(f"MaxSupT: {val_temp}!=65")
        except:
            sys_feedback.append(f"MaxSupT: {val_temp_raw} invalid")

        score += sys_score
        
        # Track fully correct systems for summary
        if sys_score == 18:
            systems_passed_count += 1
            
    feedback.append(f"Fully correct systems: {systems_passed_count}/{len(TARGET_SYSTEMS)}.")
    
    # Final check
    passed = (score >= 70) and sim_ran
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }