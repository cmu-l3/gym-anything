#!/usr/bin/env python3
"""
Verifier for configure_agv_payload_dynamics task.

A robotics engineer must update an AGV simulation to reflect the payload dynamics 
of a heavy, asymmetrical sorting conveyor module and upgrade the wheel motors.

Scoring System:
- File exists at target path: 10 points
- Payload Mass correctly set to 120.0: 20 points
- Payload CoM correctly set to [0.12, -0.05, 0.18]: 30 points
- Left Motor Torque correctly set to 80.0: 20 points
- Right Motor Torque correctly set to 80.0: 20 points

Pass Threshold: 70/100 points
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_agv_payload_dynamics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy the JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    file_exists = result.get("file_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)

    # Validate output file presence
    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Saved world file not found at /home/ga/Desktop/agv_heavy_payload.wbt. You must save using File > Save World As."
        }
    
    if not file_created_during_task:
        feedback.append("Warning: File modification timestamp is older than task start time (anti-gaming check).")

    score += 10
    feedback.append("World file saved at correct path.")

    # 1. Payload Mass
    mass = result.get("payload_mass")
    if mass is not None and abs(mass - 120.0) <= 1.0:
        score += 20
        feedback.append(f"Payload mass correctly set to {mass} kg.")
    else:
        feedback.append(f"Payload mass is {mass}, expected ~120.0 kg.")

    # 2. Payload Center of Mass (CoM)
    com = result.get("payload_com")
    expected_com = [0.12, -0.05, 0.18]
    if com is not None and len(com) == 3:
        # Check that all elements match within floating point tolerance
        if all(abs(c - e) <= 0.015 for c, e in zip(com, expected_com)):
            score += 30
            feedback.append(f"Payload centerOfMass correctly set to {com}.")
        else:
            feedback.append(f"Payload centerOfMass is {com}, expected {expected_com}.")
    else:
        feedback.append("Payload centerOfMass not found or incorrectly formatted.")

    # 3. Left Motor maxTorque
    l_torque = result.get("left_torque")
    if l_torque is not None and abs(l_torque - 80.0) <= 0.5:
        score += 20
        feedback.append(f"Left motor maxTorque correctly set to {l_torque} Nm.")
    else:
        feedback.append(f"Left motor maxTorque is {l_torque}, expected ~80.0 Nm.")

    # 4. Right Motor maxTorque
    r_torque = result.get("right_torque")
    if r_torque is not None and abs(r_torque - 80.0) <= 0.5:
        score += 20
        feedback.append(f"Right motor maxTorque correctly set to {r_torque} Nm.")
    else:
        feedback.append(f"Right motor maxTorque is {r_torque}, expected ~80.0 Nm.")

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }