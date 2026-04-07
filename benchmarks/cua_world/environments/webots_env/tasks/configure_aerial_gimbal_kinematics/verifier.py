#!/usr/bin/env python3
"""
Verifier for configure_aerial_gimbal_kinematics task.

Tests configuration of deeply nested HingeJoint RotationalMotors.
Verifies 'minPosition', 'maxPosition', and 'controlPID' for Pan, Tilt, and Roll motors.
"""

import os
import re
import json
import tempfile
import logging

logger = logging.getLogger(__name__)

def extract_motor_config(content, motor_name):
    """Extract motor parameters from a .wbt file using the motor's name."""
    # Find the motor name block
    idx = content.find(f'name "{motor_name}"')
    if idx == -1:
        return None
        
    # Find end of this block (next closing brace or next node)
    end_idx = content.find('}', idx)
    if end_idx == -1:
        block = content[idx:]
    else:
        block = content[idx:end_idx]
        
    config = {}
    
    # Extract minPosition
    min_match = re.search(r'minPosition\s+([-\d.]+)', block)
    if min_match:
        config['minPosition'] = float(min_match.group(1))
        
    # Extract maxPosition
    max_match = re.search(r'maxPosition\s+([-\d.]+)', block)
    if max_match:
        config['maxPosition'] = float(max_match.group(1))
        
    # Extract controlPID (3-element vector)
    pid_match = re.search(r'controlPID\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', block)
    if pid_match:
        config['controlPID'] = [
            float(pid_match.group(1)),
            float(pid_match.group(2)),
            float(pid_match.group(3))
        ]
        
    return config

def check_motor(config, expected_min, expected_max, expected_pid, motor_name):
    """Check parsed configuration against expected values."""
    score = 0
    feedback = []
    
    if not config:
        return 0, [f"{motor_name}: Motor configuration block not found in file."]
        
    # Check minPosition
    if 'minPosition' in config and abs(config['minPosition'] - expected_min) <= 0.01:
        score += 10
    else:
        val = config.get('minPosition', 'not found')
        feedback.append(f"{motor_name}: minPosition is {val}, expected {expected_min}")
        
    # Check maxPosition
    if 'maxPosition' in config and abs(config['maxPosition'] - expected_max) <= 0.01:
        score += 10
    else:
        val = config.get('maxPosition', 'not found')
        feedback.append(f"{motor_name}: maxPosition is {val}, expected {expected_max}")
        
    # Check controlPID
    if 'controlPID' in config:
        pid = config['controlPID']
        if (abs(pid[0] - expected_pid[0]) <= 0.01 and 
            abs(pid[1] - expected_pid[1]) <= 0.01 and 
            abs(pid[2] - expected_pid[2]) <= 0.01):
            score += 10
        else:
            feedback.append(f"{motor_name}: controlPID is {pid}, expected {expected_pid}")
    else:
        feedback.append(f"{motor_name}: controlPID not found, expected {expected_pid}")
        
    if score == 30:
        feedback.append(f"{motor_name}: Perfectly configured (+30 pts)")
        
    return score, feedback

def verify_configure_aerial_gimbal_kinematics(traj, env_info, task_info):
    """
    Verify the gimbal kinematic parameters were correctly set.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/stabilized_gimbal.wbt')
    
    pan_expected = metadata.get('pan_motor', {})
    tilt_expected = metadata.get('tilt_motor', {})
    roll_expected = metadata.get('roll_motor', {})

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
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # --- Check file existence ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world using File > Save World As."
        }

    score += 10
    feedback_parts.append("File saved successfully.")

    # --- Parse motor configurations ---
    pan_cfg = extract_motor_config(wbt_content, "pan_motor")
    tilt_cfg = extract_motor_config(wbt_content, "tilt_motor")
    roll_cfg = extract_motor_config(wbt_content, "roll_motor")

    # Check Pan
    pan_score, pan_feedback = check_motor(
        pan_cfg, 
        pan_expected['minPosition'], 
        pan_expected['maxPosition'], 
        pan_expected['controlPID'], 
        "Pan Motor"
    )
    score += pan_score
    feedback_parts.extend(pan_feedback)

    # Check Tilt
    tilt_score, tilt_feedback = check_motor(
        tilt_cfg, 
        tilt_expected['minPosition'], 
        tilt_expected['maxPosition'], 
        tilt_expected['controlPID'], 
        "Tilt Motor"
    )
    score += tilt_score
    feedback_parts.extend(tilt_feedback)

    # Check Roll
    roll_score, roll_feedback = check_motor(
        roll_cfg, 
        roll_expected['minPosition'], 
        roll_expected['maxPosition'], 
        roll_expected['controlPID'], 
        "Roll Motor"
    )
    score += roll_score
    feedback_parts.extend(roll_feedback)

    # Check anti-gaming: Did they just resave the file without edits?
    if score == 10:
        feedback_parts.append("Warning: No motor modifications detected. Did you apply the changes?")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }