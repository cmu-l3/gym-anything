#!/usr/bin/env python3
"""
Verifier for south_entrance_door_implementation task.

The agent must:
1. Define a Construction with U=0.40.
2. Add a 6x7 ft DOOR object to a Ground Floor South exterior wall.
3. Run the simulation.

Scoring:
- Simulation Ran: 10 pts
- Construction Defined (U=0.40 ± 0.02): 30 pts
- Door Object Created: 20 pts
- Dimensions Correct (6x7): 20 pts
- Correct Location (Ground South): 20 pts (Implicit in "Door Object Created" if filtered correctly, but we double check)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_south_entrance_door(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not read result file. Did the agent save the project?"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Simulation Check
    if result.get('sim_ran', False):
        score += 10
        feedback_parts.append("Simulation ran successfully (+10).")
    else:
        feedback_parts.append("Simulation not run or .SIM file not updated.")

    # Data check
    door_found = result.get('door_found', False)
    door_data = result.get('door_data', {})
    
    if not door_found:
        feedback_parts.append("No door found on Ground Floor South wall.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    # 2. Door Existence & Location (20 pts for existence + 20 for location logic in parser)
    # The parser only sets 'door_found' = True if it's on Ground + South.
    score += 40 
    feedback_parts.append("Door found on correct wall (Ground South) (+40).")

    # 3. Dimensions Check (20 pts)
    # Width = 6.0, Height = 7.0
    try:
        width = float(door_data.get('width', 0))
        height = float(door_data.get('height', 0))
        
        if abs(width - 6.0) < 0.2 and abs(height - 7.0) < 0.2:
            score += 20
            feedback_parts.append("Door dimensions correct (6x7) (+20).")
        else:
            feedback_parts.append(f"Door dimensions incorrect. Found: {width}x{height}, Expected: 6x7.")
    except (ValueError, TypeError):
        feedback_parts.append("Could not parse door dimensions.")

    # 4. Construction U-Value Check (30 pts)
    # Target 0.40 ± 0.02
    try:
        u_val = float(result.get('door_u_value', -1))
        if abs(u_val - 0.40) <= 0.02:
            score += 30
            feedback_parts.append(f"Construction U-Value correct ({u_val}) (+30).")
        else:
            feedback_parts.append(f"Construction U-Value incorrect. Found: {u_val}, Expected: 0.40.")
    except (ValueError, TypeError):
        feedback_parts.append("Could not determine door U-Value.")

    passed = score >= 60 and result.get('sim_ran', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }