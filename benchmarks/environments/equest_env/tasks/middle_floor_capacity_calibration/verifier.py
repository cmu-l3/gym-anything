#!/usr/bin/env python3
"""
Verifier for middle_floor_capacity_calibration task.

Requirements:
1. Simulation must have been run during the task session (anti-gaming).
2. All 5 Middle Floor (M.*) systems must have:
   - COOLING-CAPACITY within 84000 +/- 500
   - HEATING-CAPACITY within 100000 +/- 500

Scoring:
- Simulation run: 10 pts
- Cooling Capacity: 10 pts per system (50 total)
- Heating Capacity: 8 pts per system (40 total)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Config
TARGET_COOLING = 84000
TARGET_HEATING = 100000
TOLERANCE = 500
REQUIRED_SYSTEMS_COUNT = 5

def verify_middle_floor_capacity_calibration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env interface unavailable"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Simulation Status
    sim_ran = result.get("sim_file_is_new", False)
    if sim_ran:
        score += 10
        feedback.append("[PASS] Simulation ran during session (+10)")
    else:
        feedback.append("[FAIL] Simulation did not run or result file not saved properly (+0)")

    # 2. Check System Parameters
    systems = result.get("systems", {})
    # Filter for M. systems just in case regex caught others (though script filters them)
    m_systems = {k: v for k, v in systems.items() if k.startswith("M.")}
    
    correct_cool_count = 0
    correct_heat_count = 0
    
    for name, params in m_systems.items():
        cool_cap = params.get("cooling_capacity", -1)
        heat_cap = params.get("heating_capacity", -1)
        
        # Verify Cooling
        if abs(cool_cap - TARGET_COOLING) <= TOLERANCE:
            score += 10
            correct_cool_count += 1
        else:
            feedback.append(f"  - {name}: Cooling Capacity {cool_cap} != {TARGET_COOLING}")

        # Verify Heating
        if abs(heat_cap - TARGET_HEATING) <= TOLERANCE:
            score += 8
            correct_heat_count += 1
        else:
            feedback.append(f"  - {name}: Heating Capacity {heat_cap} != {TARGET_HEATING}")

    feedback.append(f"Systems with correct Cooling: {correct_cool_count}/{REQUIRED_SYSTEMS_COUNT}")
    feedback.append(f"Systems with correct Heating: {correct_heat_count}/{REQUIRED_SYSTEMS_COUNT}")

    # Pass logic
    # Must have run simulation AND fixed at least 3 systems correctly to pass
    passed = (score >= 60) and sim_ran and (correct_cool_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }