#!/usr/bin/env python3
"""
Verifier for configure_odometry_encoders task.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Left encoder added: 15 points
  - Left encoder resolution: 10 points
  - Right encoder added: 15 points
  - Right encoder resolution: 10 points
  - Motors maxTorque set to 25.0: 20 points
  - Motors maxVelocity set to 5.0: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_odometry_encoders(traj, env_info, task_info):
    """
    Verify the odometry encoders world was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/hospital_robot_odometry.wbt')
    expected_resolution = metadata.get('expected_resolution', 0.00153)
    expected_max_velocity = metadata.get('expected_max_velocity', 5.0)
    expected_max_torque = metadata.get('expected_max_torque', 25.0)

    score = 0
    feedback_parts = []

    # --- Copy the .wbt file independently ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    # --- Check file existence ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }

    score += 10
    feedback_parts.append("World file saved at correct path")

    # Parse PositionSensor blocks
    sensor_blocks = re.findall(r'PositionSensor\s*\{([^}]+)\}', wbt_content)
    
    left_encoder_found = False
    left_encoder_res = False
    right_encoder_found = False
    right_encoder_res = False
    
    for block in sensor_blocks:
        name_match = re.search(r'name\s+"([^"]+)"', block)
        if name_match:
            name = name_match.group(1)
            res_match = re.search(r'resolution\s+([\d.]+)', block)
            res_val = float(res_match.group(1)) if res_match else None
            
            if name == "left_encoder":
                left_encoder_found = True
                if res_val is not None and abs(res_val - expected_resolution) < 0.00002:
                    left_encoder_res = True
            elif name == "right_encoder":
                right_encoder_found = True
                if res_val is not None and abs(res_val - expected_resolution) < 0.00002:
                    right_encoder_res = True

    if left_encoder_found:
        score += 15
        feedback_parts.append("Left encoder added")
        if left_encoder_res:
            score += 10
            feedback_parts.append(f"Left encoder resolution correct ({expected_resolution})")
        else:
            feedback_parts.append(f"Left encoder resolution incorrect, expected {expected_resolution}")
    else:
        feedback_parts.append("Left encoder not found")

    if right_encoder_found:
        score += 15
        feedback_parts.append("Right encoder added")
        if right_encoder_res:
            score += 10
            feedback_parts.append(f"Right encoder resolution correct ({expected_resolution})")
        else:
            feedback_parts.append(f"Right encoder resolution incorrect, expected {expected_resolution}")
    else:
        feedback_parts.append("Right encoder not found")

    # Parse RotationalMotor blocks
    motor_blocks = re.findall(r'RotationalMotor\s*\{([^}]+)\}', wbt_content)
    
    left_motor_vel = False
    left_motor_tor = False
    right_motor_vel = False
    right_motor_tor = False
    
    for block in motor_blocks:
        name_match = re.search(r'name\s+"([^"]+)"', block)
        if name_match:
            name = name_match.group(1)
            vel_match = re.search(r'maxVelocity\s+([\d.]+)', block)
            tor_match = re.search(r'maxTorque\s+([\d.]+)', block)
            
            vel_val = float(vel_match.group(1)) if vel_match else None
            tor_val = float(tor_match.group(1)) if tor_match else None
            
            if name == "left_motor":
                if vel_val is not None and abs(vel_val - expected_max_velocity) < 0.1:
                    left_motor_vel = True
                if tor_val is not None and abs(tor_val - expected_max_torque) < 0.1:
                    left_motor_tor = True
            elif name == "right_motor":
                if vel_val is not None and abs(vel_val - expected_max_velocity) < 0.1:
                    right_motor_vel = True
                if tor_val is not None and abs(tor_val - expected_max_torque) < 0.1:
                    right_motor_tor = True

    if left_motor_tor and right_motor_tor:
        score += 20
        feedback_parts.append(f"Both motors maxTorque correct ({expected_max_torque})")
    else:
        feedback_parts.append(f"Motors maxTorque incorrect, expected {expected_max_torque}")

    if left_motor_vel and right_motor_vel:
        score += 20
        feedback_parts.append(f"Both motors maxVelocity correct ({expected_max_velocity})")
    else:
        feedback_parts.append(f"Motors maxVelocity incorrect, expected {expected_max_velocity}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }