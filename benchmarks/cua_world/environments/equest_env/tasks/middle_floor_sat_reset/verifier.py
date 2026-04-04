#!/usr/bin/env python3
"""
Verifier for middle_floor_sat_reset task.

Requirements:
1. Simulation must run during the session (.SIM file timestamp check).
2. All 5 Middle Floor (M.*) systems must have:
   - COOL-SET-T = 60.0 (+/- 0.5)
   - HEAT-SET-T = 90.0 (+/- 0.5)

Scoring (100 pts total):
- 10 pts: Simulation ran
- 9 pts: M.S21 COOL-SET-T correct
- 9 pts: M.S21 HEAT-SET-T correct
- ... (repeated for all 5 systems) ...
Total: 10 + (5 systems * 2 params * 9 pts) = 100 pts.

Pass Threshold: 60 points AND simulation ran.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# This path corresponds to where export_result.ps1 saves the file inside the VM
# We will copy it out to verify.
RESULT_PATH_IN_VM = r"C:\Users\Docker\middle_floor_sat_reset_result.json"

TARGET_SYSTEMS = ["M.S21", "M.E22", "M.N23", "M.W24", "M.C25"]
TARGET_COOL = 60.0
TARGET_HEAT = 90.0
TOLERANCE = 0.5


def verify_middle_floor_sat_reset(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Copy result file from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH_IN_VM, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file not found. Did the task script run successfully?"
        }
    except json.JSONDecodeError:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Result file is not valid JSON."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify Simulation (10 pts)
    sim_ran = result.get("sim_file_is_new", False)
    if sim_ran:
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run during this session (0/10).")

    # 2. Verify System Parameters (90 pts total)
    systems_data = result.get("systems", {})
    
    for sys_name in TARGET_SYSTEMS:
        sys_data = systems_data.get(sys_name, {})
        
        # Verify COOL-SET-T
        cool_val = float(sys_data.get("cool_set_t", -1))
        if abs(cool_val - TARGET_COOL) <= TOLERANCE:
            score += 9
        else:
            feedback.append(f"{sys_name}: COOL-SET-T is {cool_val}, expected {TARGET_COOL}.")

        # Verify HEAT-SET-T
        heat_val = float(sys_data.get("heat_set_t", -1))
        if abs(heat_val - TARGET_HEAT) <= TOLERANCE:
            score += 9
        else:
            feedback.append(f"{sys_name}: HEAT-SET-T is {heat_val}, expected {TARGET_HEAT}.")

    # Final Evaluation
    # Pass condition: Score >= 60 AND Simulation Ran
    passed = (score >= 60) and sim_ran
    
    if passed:
        feedback.insert(0, "Task PASSED.")
    else:
        feedback.insert(0, "Task FAILED.")
        if not sim_ran:
            feedback.append("CRITICAL: Simulation must be run to pass.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }