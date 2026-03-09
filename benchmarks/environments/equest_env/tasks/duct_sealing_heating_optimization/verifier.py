#!/usr/bin/env python3
"""
Verifier for duct_sealing_heating_optimization task.

Criteria:
1. Simulation ran during session (10 pts)
2. SUPPLY-STATIC = 2.0 (±0.1) for all 15 systems (3 pts each -> 45 total)
3. MAX-SUPPLY-T = 100 (±1.0) for all 15 systems (3 pts each -> 45 total)

Total: 100 pts.
Pass: Score >= 60 AND Simulation Ran AND at least 8 systems have correct static pressure.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\duct_sealing_heating_optimization_result.json"

def verify_duct_sealing_heating_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result file: {e}. Did the task complete successfully?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Simulation (10 pts)
    sim_ran = result.get('sim_file_is_new', False)
    if sim_ran:
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run or was not saved during the session (0 pts).")

    # 2. Analyze Systems
    systems = result.get('systems_analyzed', [])
    
    # Target counts
    target_static = 2.0
    target_max_t = 100.0
    
    correct_static_count = 0
    correct_temp_count = 0
    
    # Helper to check floor
    def get_floor(name):
        if "(G." in name: return "Ground"
        if "(M." in name: return "Middle"
        if "(T." in name: return "Top"
        return "Unknown"

    for sys in systems:
        name = sys.get('name', 'Unknown')
        
        # Check SUPPLY-STATIC
        try:
            val_s = float(sys.get('supply_static', -1))
            if abs(val_s - target_static) <= 0.1:
                score += 3
                correct_static_count += 1
        except (ValueError, TypeError):
            pass
            
        # Check MAX-SUPPLY-T
        try:
            val_t = float(sys.get('max_supply_t', -1))
            if abs(val_t - target_max_t) <= 1.0:
                score += 3
                correct_temp_count += 1
        except (ValueError, TypeError):
            pass

    feedback.append(f"Correct SUPPLY-STATIC: {correct_static_count}/15 systems (+{correct_static_count*3}).")
    feedback.append(f"Correct MAX-SUPPLY-T: {correct_temp_count}/15 systems (+{correct_temp_count*3}).")

    # Pass Condition
    # Must have score >= 60 AND Sim Ran AND majority of static pressure work done
    passed = (score >= 60) and sim_ran and (correct_static_count >= 8)
    
    if not sim_ran:
        feedback.append("FAIL: Simulation required for passing.")
    if correct_static_count < 8:
        feedback.append("FAIL: Fewer than 8 systems had correct static pressure.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }