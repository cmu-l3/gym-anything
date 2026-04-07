#!/usr/bin/env python3
"""
Verifier for configure_underactuated_gripper task.

A prosthetics robotics engineer must configure a tendon-driven, under-actuated robotic
finger in Webots. Requires linking 3 RotationalMotors by assigning them the same name,
increasing their torque, and setting progressive multipliers.

Scoring (100 points total):
  - File saved at correct path and modified during task: 10 points
  - Motor names coupled (exactly 3 motors named "tendon_drive"): 30 points
  - Torque increased (all 3 motors have maxTorque 15): 30 points
  - Multipliers correct (contains 1.5 and 2.0 values): 30 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def parse_motors(wbt_content):
    """Safely extracts the contents of all RotationalMotor blocks from a .wbt file."""
    motors = []
    blocks = wbt_content.split('RotationalMotor')
    for b in blocks[1:]:
        start = b.find('{')
        if start == -1:
            continue
        depth = 0
        end = -1
        for i in range(start, len(b)):
            if b[i] == '{':
                depth += 1
            elif b[i] == '}':
                depth -= 1
                if depth == 0:
                    end = i
                    break
        if end != -1:
            motors.append(b[start:end+1])
    return motors

def verify_configure_underactuated_gripper(traj, env_info, task_info):
    """
    Verify that the under-actuated gripper was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/coupled_finger.wbt')
    expected_motor_name = metadata.get('expected_motor_name', 'tendon_drive')
    expected_torque = float(metadata.get('expected_torque', 15.0))
    expected_multipliers = set([float(x) for x in metadata.get('expected_multipliers', [1.0, 1.5, 2.0])])

    score = 0
    feedback_parts = []
    
    # Check export json for anti-gaming (file creation timestamp)
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env('/tmp/configure_underactuated_gripper_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(temp_json.name)
    except Exception:
        export_result = {}

    if not export_result.get("created_during_task", True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file was not modified during the task execution."
        }

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

    # --- Parse all RotationalMotors ---
    motors = parse_motors(wbt_content)
    
    if not motors:
        return {
            "passed": False,
            "score": score,
            "feedback": "No RotationalMotor nodes found in the saved world."
        }
        
    coupled_motors = []
    for m in motors:
        name_match = re.search(r'name\s+"([^"]+)"', m)
        if name_match and name_match.group(1) == expected_motor_name:
            coupled_motors.append(m)

    # --- Criterion 1: Motor names coupled ---
    num_coupled = len(coupled_motors)
    if num_coupled == 3:
        score += 30
        feedback_parts.append(f"Successfully coupled 3 motors with name '{expected_motor_name}'")
    elif num_coupled > 0:
        feedback_parts.append(f"Only {num_coupled}/3 motors have the name '{expected_motor_name}'")
    else:
        feedback_parts.append(f"No motors found with the name '{expected_motor_name}'")

    if num_coupled > 0:
        # --- Check Torques and Multipliers within the coupled motors ---
        valid_torques = 0
        actual_multipliers = set()
        
        for m in coupled_motors:
            torque_match = re.search(r'maxTorque\s+([\d.]+)', m)
            if torque_match and float(torque_match.group(1)) == expected_torque:
                valid_torques += 1
                
            mult_match = re.search(r'multiplier\s+([\d.]+)', m)
            if mult_match:
                actual_multipliers.add(float(mult_match.group(1)))
            else:
                # Default multiplier in Webots is 1.0 if not specified
                actual_multipliers.add(1.0)
                
        # --- Criterion 2: Torque increased ---
        if valid_torques == 3:
            score += 30
            feedback_parts.append(f"All 3 coupled motors have maxTorque set to {expected_torque}")
        elif valid_torques > 0:
            feedback_parts.append(f"Only {valid_torques}/3 coupled motors have maxTorque {expected_torque}")
        else:
            feedback_parts.append(f"Coupled motors do not have maxTorque {expected_torque}")
            
        # --- Criterion 3: Multipliers correct ---
        # We look for at least the 1.5 and 2.0 multipliers (1.0 is default/base)
        if 1.5 in actual_multipliers and 2.0 in actual_multipliers:
            score += 30
            feedback_parts.append("Progressive multipliers (1.5, 2.0) correctly configured")
        else:
            feedback_parts.append(f"Missing required multipliers. Found: {sorted(list(actual_multipliers))}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }