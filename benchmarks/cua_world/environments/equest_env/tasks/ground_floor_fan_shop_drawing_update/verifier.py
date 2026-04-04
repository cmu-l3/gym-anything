#!/usr/bin/env python3
"""
Verifier for ground_floor_fan_shop_drawing_update task.

The agent must update 5 Ground Floor HVAC systems (G.S1 - G.C5) with:
1. FAN-PLACEMENT = BLOW-THROUGH
2. SUPPLY-STATIC = 2.75
3. SUPPLY-EFF = 0.62

Scoring (100 points total):
- Simulation ran during session: 10 pts
- Fan Placement Correct (5 systems * 6 pts): 30 pts
- Static Pressure Correct (5 systems * 6 pts): 30 pts
- Efficiency Correct (5 systems * 6 pts): 30 pts

Pass Threshold: 60 points AND simulation ran.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Path inside the container (Windows path mapped via Docker usually, 
# but here we access the exported JSON file)
RESULT_FILENAME = "task_result.json"
CONTAINER_RESULT_PATH = "C:\\Users\\Docker\\task_result.json"

TARGET_SYSTEMS = ["G.S1", "G.E2", "G.N3", "G.W4", "G.C5"]
TARGET_PLACEMENT = "BLOW-THROUGH"
TARGET_STATIC = 2.75
TARGET_EFF = 0.62

TOLERANCE_STATIC = 0.05
TOLERANCE_EFF = 0.01

def verify_ground_floor_fan_update(traj, env_info, task_info):
    """
    Verify the eQUEST fan update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(CONTAINER_RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task results. Did the task complete successfully?"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Simulation Run (10 pts)
    if result.get('sim_file_is_new', False):
        score += 10
        feedback.append("Simulation ran successfully.")
    else:
        feedback.append("Simulation NOT run (or not saved).")

    systems_data = result.get('systems', {})
    
    placement_score = 0
    static_score = 0
    eff_score = 0
    
    for sys_name in TARGET_SYSTEMS:
        sys_data = systems_data.get(sys_name)
        
        if not isinstance(sys_data, dict):
            feedback.append(f"System {sys_name} not found in model.")
            continue
            
        # Check Fan Placement
        act_placement = sys_data.get('fan_placement', 'UNKNOWN')
        if act_placement == TARGET_PLACEMENT:
            placement_score += 6
        
        # Check Static Pressure
        try:
            act_static = float(sys_data.get('supply_static', -1))
            if abs(act_static - TARGET_STATIC) <= TOLERANCE_STATIC:
                static_score += 6
        except (ValueError, TypeError):
            pass
            
        # Check Efficiency
        try:
            act_eff = float(sys_data.get('supply_eff', -1))
            if abs(act_eff - TARGET_EFF) <= TOLERANCE_EFF:
                eff_score += 6
        except (ValueError, TypeError):
            pass

    score += placement_score
    score += static_score
    score += eff_score
    
    feedback.append(f"Fan Placement Score: {placement_score}/30")
    feedback.append(f"Static Pressure Score: {static_score}/30")
    feedback.append(f"Efficiency Score: {eff_score}/30")
    
    passed = (score >= 60) and result.get('sim_file_is_new', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }