#!/usr/bin/env python3
"""
Verifier for bas_optimum_start_upgrade task.

Task: Implement Optimum Start on 15 HVAC systems (G.*, M.*, T.*) in eQUEST.
Required Settings:
- OPTIMUM-START = YES
- OP-START-TIME = 3
- HEAT-START-GRAD = 4.0
- COOL-START-GRAD = 3.5

Scoring:
- Simulation ran during session: 10 pts
- Ground Floor Systems (5) updated correctly: 30 pts (6 pts each)
- Middle Floor Systems (5) updated correctly: 30 pts (6 pts each)
- Top Floor Systems (5) updated correctly: 30 pts (6 pts each)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\bas_optimum_start_upgrade_result.json"

# Expected targets
TARGETS = {
    "OPTIMUM-START": "YES",
    "OP-START-TIME": 3,      # Integer match
    "HEAT-START-GRAD": 4.0,  # Float match with tolerance
    "COOL-START-GRAD": 3.5   # Float match with tolerance
}

def verify_bas_optimum_start_upgrade(traj, env_info, task_info):
    """
    Verify the eQUEST BAS optimum start upgrade.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results (export may have failed): {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Simulation Status (10 pts)
    if result.get('sim_file_is_new', False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10)")
    else:
        feedback_parts.append("Simulation NOT run during task (0/10)")

    # 3. Check System Parameters (90 pts total)
    systems_data = result.get('systems', {})
    
    # Group systems by floor for feedback
    floors = {'G': [], 'M': [], 'T': []}
    for name in systems_data.keys():
        prefix = name.split('.')[0] if '.' in name else ''
        if prefix in floors:
            floors[prefix].append(name)

    total_systems_checked = 0
    total_systems_correct = 0
    
    for prefix, system_names in floors.items():
        floor_score = 0
        floor_correct_count = 0
        
        # We expect 5 systems per floor
        if not system_names:
            feedback_parts.append(f"No {prefix} systems found/modified")
            continue

        for sys_name in system_names:
            sys_data = systems_data[sys_name]
            sys_correct = True
            issues = []

            # Check OPTIMUM-START
            if str(sys_data.get('OPTIMUM-START', '')).upper() != TARGETS['OPTIMUM-START']:
                sys_correct = False
                issues.append("OptStart!=YES")

            # Check OP-START-TIME
            try:
                val = float(sys_data.get('OP-START-TIME', 0))
                if abs(val - TARGETS['OP-START-TIME']) > 0.1:
                    sys_correct = False
                    issues.append(f"Time {val}!=3")
            except:
                sys_correct = False

            # Check HEAT-START-GRAD
            try:
                val = float(sys_data.get('HEAT-START-GRAD', 0))
                if abs(val - TARGETS['HEAT-START-GRAD']) > 0.1:
                    sys_correct = False
                    issues.append(f"HeatGrad {val}!=4.0")
            except:
                sys_correct = False

            # Check COOL-START-GRAD
            try:
                val = float(sys_data.get('COOL-START-GRAD', 0))
                if abs(val - TARGETS['COOL-START-GRAD']) > 0.1:
                    sys_correct = False
                    issues.append(f"CoolGrad {val}!=3.5")
            except:
                sys_correct = False

            if sys_correct:
                floor_score += 6
                floor_correct_count += 1
                total_systems_correct += 1
            
            total_systems_checked += 1

        score += floor_score
        if floor_correct_count == 5:
            feedback_parts.append(f"{prefix}-Floor systems: All 5 correct (+30)")
        else:
            feedback_parts.append(f"{prefix}-Floor systems: {floor_correct_count}/5 correct (+{floor_score})")

    # Final Score Calculation
    passed = score >= 70
    
    final_feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }