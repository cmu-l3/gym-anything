#!/usr/bin/env python3
"""
Verifier for restroom_exhaust_fan_retrofit task.

The agent must:
1. Add mechanical exhaust to Core zones on 4 floors (Ground, 2nd, 3rd, Top).
2. Set EXHAUST-FLOW = 300 CFM.
3. Set EXHAUST-STATIC = 0.5 in. w.c.
4. Run the simulation (resulting in a new .SIM file).

Scoring (100 points):
- Simulation ran: 20 pts
- Correct Core Zones (Flow=300, Static=0.5): 20 pts per floor (max 4 floors = 80 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the container where the PS1 script saves the result
RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

def verify_restroom_exhaust_fan_retrofit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result (task likely not completed): {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Simulation (20 pts)
    sim_ran = result.get('simulation_ran', False)
    if sim_ran:
        score += 20
        feedback_parts.append("Simulation ran successfully (+20)")
    else:
        feedback_parts.append("Simulation did NOT run or save results (0/20)")

    # 2. Check Zones (80 pts total, 20 per zone)
    # Expecting 4 zones (one per floor)
    correct_zones = result.get('correct_zones_list', [])
    count = len(correct_zones)
    
    # Cap at 4 floors for scoring purposes
    scored_count = min(count, 4)
    zone_score = scored_count * 20
    score += zone_score
    
    if count == 0:
        feedback_parts.append("No Core zones found with EXHAUST-FLOW=300 and STATIC=0.5")
    else:
        feedback_parts.append(f"Found {count} correctly updated Core zones (+{zone_score})")
        if count < 4:
            feedback_parts.append(f"Target was 4 zones (one per floor), found {count}")

    # Pass logic: Must run simulation AND get at least 3/4 floors correct (Score >= 80)
    passed = (score >= 80) and sim_ran
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "correct_zones": correct_zones,
            "simulation_ran": sim_ran
        }
    }