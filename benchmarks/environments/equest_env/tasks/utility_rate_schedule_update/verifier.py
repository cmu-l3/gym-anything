#!/usr/bin/env python3
"""
Verifier for utility_rate_schedule_update task.

The agent must update utility rate parameters in eQUEST and run a simulation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the Windows container
RESULT_PATH = "C:\\Users\\Docker\\utility_rate_schedule_update_result.json"

def verify_utility_rate_schedule_update(traj, env_info, task_info):
    """
    Verifies that:
    1. Simulation was run (SIM file is new).
    2. Electric utility rate parameters are updated correctly.
    3. Fuel utility rate parameters are updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load targets and tolerances from metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {
        "elec_energy_chg": 0.148,
        "elec_demand_chg": 19.25,
        "elec_ratchet": 0.65,
        "fuel_energy_chg": 1.42,
        "fuel_min_charge": 125.0
    })
    tols = metadata.get('tolerances', {
        "energy_chg": 0.002,
        "demand_chg": 0.10,
        "ratchet": 0.02,
        "min_charge": 1.0
    })

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve task result file. Did the task complete successfully?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Check Simulation (15 points)
    if result.get('sim_file_is_new', False):
        score += 15
        feedback_parts.append("Simulation ran successfully (+15).")
    else:
        feedback_parts.append("Simulation NOT run (or project not saved) (0/15).")

    # 2. Check Electric Energy Charge (20 points)
    val = result.get('elec_energy_chg', -1)
    target = targets['elec_energy_chg']
    if abs(val - target) <= tols['energy_chg']:
        score += 20
        feedback_parts.append(f"Elec Energy Charge correct ({val}) (+20).")
    else:
        feedback_parts.append(f"Elec Energy Charge incorrect: got {val}, expected {target} (0/20).")

    # 3. Check Electric Demand Charge (20 points)
    val = result.get('elec_demand_chg', -1)
    target = targets['elec_demand_chg']
    if abs(val - target) <= tols['demand_chg']:
        score += 20
        feedback_parts.append(f"Elec Demand Charge correct ({val}) (+20).")
    else:
        feedback_parts.append(f"Elec Demand Charge incorrect: got {val}, expected {target} (0/20).")

    # 4. Check Electric Ratchet (15 points)
    val = result.get('elec_ratchet', -1)
    target = targets['elec_ratchet']
    if abs(val - target) <= tols['ratchet']:
        score += 15
        feedback_parts.append(f"Elec Ratchet correct ({val}) (+15).")
    else:
        feedback_parts.append(f"Elec Ratchet incorrect: got {val}, expected {target} (0/15).")

    # 5. Check Fuel Energy Charge (20 points)
    val = result.get('fuel_energy_chg', -1)
    target = targets['fuel_energy_chg']
    if abs(val - target) <= tols['energy_chg']:
        score += 20
        feedback_parts.append(f"Fuel Energy Charge correct ({val}) (+20).")
    else:
        feedback_parts.append(f"Fuel Energy Charge incorrect: got {val}, expected {target} (0/20).")

    # 6. Check Fuel Min Charge (10 points)
    val = result.get('fuel_min_charge', -1)
    target = targets['fuel_min_charge']
    if abs(val - target) <= tols['min_charge']:
        score += 10
        feedback_parts.append(f"Fuel Min Charge correct ({val}) (+10).")
    else:
        feedback_parts.append(f"Fuel Min Charge incorrect: got {val}, expected {target} (0/10).")

    # Pass logic: Score >= 60 AND Simulation Ran
    passed = (score >= 60) and result.get('sim_file_is_new', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }