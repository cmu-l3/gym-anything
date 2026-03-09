#!/usr/bin/env python3
"""
Verifier for dhw_loop_temperature_and_pump_retrofit task.

Criteria:
1. Simulation ran during the session (Anti-gaming).
2. DHW Loop Temperature set to 120°F (±0.5).
3. DHW Pump Head set to 20 ft (±0.5).
4. DHW Pump Mechanical Efficiency set to 0.75 (±0.01).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dhw_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Define paths
    result_remote_path = "C:\\Users\\Docker\\task_result.json"
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results. Did you save the project? Error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract values
    sim_ran = result.get('sim_ran', False)
    loop_temp = float(result.get('dhw_loop_temp', -1))
    pump_head = float(result.get('pump_head', -1))
    pump_eff = float(result.get('pump_eff', -1))

    score = 0
    feedback = []

    # Criterion 1: Simulation Run (10 pts)
    if sim_ran:
        score += 10
        feedback.append("Simulation run confirmed (+10).")
    else:
        feedback.append("Simulation did not run during this session (0/10).")

    # Criterion 2: Loop Temperature (30 pts)
    # Target: 120
    if 119.5 <= loop_temp <= 120.5:
        score += 30
        feedback.append(f"DHW Loop Temp correct: {loop_temp} F (+30).")
    elif loop_temp == -1:
        feedback.append("DHW Loop Temp not found (0/30).")
    else:
        feedback.append(f"DHW Loop Temp incorrect: {loop_temp} F (Expected 120) (0/30).")

    # Criterion 3: Pump Head (30 pts)
    # Target: 20
    if 19.5 <= pump_head <= 20.5:
        score += 30
        feedback.append(f"Pump Head correct: {pump_head} ft (+30).")
    elif pump_head == -1:
        feedback.append("DHW Pump Head not found (0/30).")
    else:
        feedback.append(f"Pump Head incorrect: {pump_head} ft (Expected 20) (0/30).")

    # Criterion 4: Pump Efficiency (30 pts)
    # Target: 0.75
    if 0.74 <= pump_eff <= 0.76:
        score += 30
        feedback.append(f"Pump Efficiency correct: {pump_eff} (+30).")
    elif pump_eff == -1:
        feedback.append("DHW Pump Efficiency not found (0/30).")
    else:
        feedback.append(f"Pump Efficiency incorrect: {pump_eff} (Expected 0.75) (0/30).")

    # Determine Pass/Fail
    # Must run simulation AND get at least 70 points (meaning at least 2/3 parameters correct + sim)
    passed = sim_ran and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }