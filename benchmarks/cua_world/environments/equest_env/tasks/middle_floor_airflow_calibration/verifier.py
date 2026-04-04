#!/usr/bin/env python3
"""
Verifier for middle_floor_airflow_calibration task.

Verifies:
1. Simulation was run during the task session (anti-gaming).
2. SUPPLY-FLOW values match specific targets for 5 systems.
3. SUPPLY-STATIC values match 2.5 for all 5 systems.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_middle_floor_airflow_calibration(traj, env_info, task_info):
    """
    Verify the airflow calibration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', {})
    tolerance_flow = metadata.get('tolerance_flow', 25)
    tolerance_static = metadata.get('tolerance_static', 0.1)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}. Ensure the project was saved."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Simulation (10 pts)
    sim_run = result.get('simulation_run_during_task', False)
    if sim_run:
        score += 10
        feedback.append("Simulation run successfully.")
    else:
        feedback.append("Simulation NOT run during task (or output file not updated).")

    # 2. Verify System Parameters (90 pts total)
    # 5 systems * 2 params * 9 pts each = 90 pts
    
    parsed_systems = result.get('systems', {})
    correct_flow_count = 0
    
    for sys_name, expected in targets.items():
        sys_data = parsed_systems.get(sys_name, {})
        actual_flow = sys_data.get('flow', -1)
        actual_static = sys_data.get('static', -1)
        
        # Check Flow (9 pts)
        if actual_flow != -1 and abs(actual_flow - expected['flow']) <= tolerance_flow:
            score += 9
            correct_flow_count += 1
            feedback.append(f"{sys_name} Flow OK ({actual_flow}).")
        else:
            feedback.append(f"{sys_name} Flow INCORRECT (Expected {expected['flow']}, Got {actual_flow}).")
            
        # Check Static (9 pts)
        if actual_static != -1 and abs(actual_static - expected['static']) <= tolerance_static:
            score += 9
            feedback.append(f"{sys_name} Static OK ({actual_static}).")
        else:
            feedback.append(f"{sys_name} Static INCORRECT (Expected {expected['static']}, Got {actual_static}).")

    # Pass logic: Score >= 60 AND Simulation Run AND at least 3 flows correct
    passed = (score >= 60) and sim_run and (correct_flow_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }