#!/usr/bin/env python3
"""
Verifier for middle_floor_dcv_implementation task.

The agent must:
1. Enable DCV-RETURN-SENSOR on 5 Middle Floor systems (M.*)
2. Set CO2 Limit to 1000 ppm
3. Run Simulation (generate new .SIM file)
4. Save Project

Scoring (100 pts):
- Simulation run: 10 pts
- Per System (5 systems):
    - OA Method correct: 10 pts (50 total)
    - CO2 Limit correct: 8 pts (40 total)

Pass Threshold: 60 pts + Simulation Run + >=3 Systems with DCV enabled
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
EXPECTED_OA_METHOD = "DCV-RETURN-SENSOR"
EXPECTED_CO2_LIMIT = 1000
CO2_TOLERANCE = 50
TARGET_SYSTEMS = ["M.S16", "M.E17", "M.N18", "M.W19", "M.C20"]
RESULT_PATH = "C:\\Users\\Docker\\middle_floor_dcv_result.json"

def verify_middle_floor_dcv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result file: {str(e)}. Did the agent save the project?"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Simulation Run
    sim_run = result.get("sim_file_exists", False)
    if sim_run:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation NOT run (0/10)")

    # 2. Verify Systems
    systems_data = result.get("systems", {})
    dcv_enabled_count = 0
    
    for sys_name in TARGET_SYSTEMS:
        sys_data = systems_data.get(sys_name, {})
        sys_feedback = []
        
        # Check OA Method
        oa_method = sys_data.get("MIN-OA-METHOD", "Missing")
        if oa_method == EXPECTED_OA_METHOD:
            score += 10
            dcv_enabled_count += 1
            sys_feedback.append("DCV OK")
        else:
            sys_feedback.append(f"OA Method '{oa_method}'")

        # Check CO2 Limit
        co2_val_str = sys_data.get("CO2-LIMIT", "0")
        try:
            co2_val = float(co2_val_str)
        except ValueError:
            co2_val = 0
            
        if abs(co2_val - EXPECTED_CO2_LIMIT) <= CO2_TOLERANCE:
            score += 8
            sys_feedback.append("CO2 OK")
        else:
            sys_feedback.append(f"CO2 {co2_val}")

        # Add brief feedback for failures
        if len(sys_feedback) < 2 or "Missing" in sys_feedback:
            # Only log detailed issues if something is wrong to keep feedback concise
            pass

    feedback_parts.append(f"DCV Enabled on {dcv_enabled_count}/5 systems")

    # Pass logic
    # Must have run sim AND enabled DCV on at least 3 systems AND score >= 60
    passed = (score >= 60) and sim_run and (dcv_enabled_count >= 3)
    
    if not sim_run:
        feedback_parts.append("FAIL: Simulation must be run to pass.")

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }