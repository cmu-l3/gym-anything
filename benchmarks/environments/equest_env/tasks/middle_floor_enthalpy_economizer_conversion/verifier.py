#!/usr/bin/env python3
"""
Verifier for middle_floor_enthalpy_economizer_conversion task.

VERIFICATION LOGIC:
1. Check if simulation ran during task (sim_file_new = True) [10 pts]
2. Verify OA-CONTROL = ENTHALPY for all 5 middle floor systems [10 pts each = 50 pts]
3. Verify ENTHALPY-LIMIT = 28 for all 5 middle floor systems [8 pts each = 40 pts]

Pass Threshold: 60 points AND simulation ran AND at least 3 systems converted.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_middle_floor_enthalpy_economizer_conversion(traj, env_info, task_info):
    """
    Verifies that the agent converted middle floor systems to enthalpy economizer control.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    expected_limit = 28.0
    tolerance = 0.5
    target_systems = ["M.S21", "M.E22", "M.N23", "M.W24", "M.C25"]

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify Simulation Run (10 pts)
    sim_ran = result.get("sim_file_new", False)
    if sim_ran:
        score += 10
        feedback_parts.append("Simulation ran successfully (+10).")
    else:
        feedback_parts.append("Simulation did NOT run or save during session (0/10).")

    # 3. Verify System Parameters
    systems_data = result.get("systems", {})
    systems_converted_count = 0
    
    for sys_tag in target_systems:
        sys_data = systems_data.get(sys_tag, {})
        
        if not sys_data.get("found", False):
            feedback_parts.append(f"System {sys_tag} not found in project file.")
            continue
            
        # Check OA-CONTROL (10 pts)
        oa_control = sys_data.get("oa_control", "UNKNOWN")
        if oa_control == "ENTHALPY":
            score += 10
            systems_converted_count += 1
            # Check Limit only if control is correct (8 pts)
            limit = sys_data.get("enthalpy_limit", -1)
            try:
                limit = float(limit)
                if abs(limit - expected_limit) <= tolerance:
                    score += 8
                else:
                    feedback_parts.append(f"{sys_tag}: Limit {limit} != {expected_limit}.")
            except (ValueError, TypeError):
                 feedback_parts.append(f"{sys_tag}: Invalid limit value.")
        else:
            feedback_parts.append(f"{sys_tag}: Control is {oa_control} (expected ENTHALPY).")

    # 4. Final Scoring
    if systems_converted_count == 5:
        feedback_parts.append("All 5 systems converted correctly.")
    else:
        feedback_parts.append(f"Only {systems_converted_count}/5 systems converted.")

    # Pass Criteria
    passed = (score >= 60) and sim_ran and (systems_converted_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }