#!/usr/bin/env python3
"""
Verifier for configure_robot_suspension task.

A vehicle dynamics engineer must correctly configure the suspension parameters
of a rover for 4 separate HingeJoints.

Scoring (100 points total):
  - File saved at correct path during the task timeframe: 10 points
  - All 4 joints have suspensionAxis = 0 0 1: 30 points (7.5 pts/joint)
  - All 4 joints have suspensionSpringConstant ~10000: 30 points (7.5 pts/joint)
  - All 4 joints have suspensionDampingConstant ~800: 30 points (7.5 pts/joint)
  - Anti-gaming: Ensure rotational axis (1 0 0) wasn't mistakenly altered.

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def extract_joint_params(content: str, joint_name: str):
    """Parses HingeJointParameters block for a given joint DEF name."""
    idx = content.find(f"DEF {joint_name}")
    if idx == -1:
        return None
        
    param_idx = content.find("HingeJointParameters {", idx)
    if param_idx == -1 or param_idx > idx + 500:
        return None
        
    block_end = content.find("}", param_idx)
    block = content[param_idx:block_end]
    
    params = {}
    
    # Parse vector properties
    axis_m = re.search(r'axis\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', block)
    if axis_m:
        params['axis'] = [float(axis_m.group(1)), float(axis_m.group(2)), float(axis_m.group(3))]
        
    susp_axis_m = re.search(r'suspensionAxis\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', block)
    if susp_axis_m:
        params['suspensionAxis'] = [float(susp_axis_m.group(1)), float(susp_axis_m.group(2)), float(susp_axis_m.group(3))]
        
    # Parse scalar properties
    spring_m = re.search(r'suspensionSpringConstant\s+([\d.-]+)', block)
    if spring_m:
        params['spring'] = float(spring_m.group(1))
        
    damping_m = re.search(r'suspensionDampingConstant\s+([\d.-]+)', block)
    if damping_m:
        params['damping'] = float(damping_m.group(1))
        
    return params


def verify_configure_robot_suspension(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/rover_fixed.wbt')
    joints = metadata.get('joints', [])
    
    exp_axis = metadata.get('expected_suspension_axis', [0.0, 0.0, 1.0])
    exp_spring = metadata.get('expected_spring_constant', 10000.0)
    exp_damping = metadata.get('expected_damping_constant', 800.0)
    
    spring_tol = metadata.get('spring_tolerance', 500.0)
    damping_tol = metadata.get('damping_tolerance', 50.0)
    starting_axis = metadata.get('starting_axis', [1.0, 0.0, 0.0])

    score = 0
    feedback_parts = []
    
    # --- Step 1: Read the export script's JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    
    try:
        copy_from_env('/tmp/configure_robot_suspension_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result = {}

    file_exists = result.get('file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world using File > Save World As."
        }
        
    if not file_created_during_task:
        feedback_parts.append("Warning: Output file timestamp indicates it might not have been created during this task session.")
    else:
        score += 10
        feedback_parts.append("Valid world file saved.")

    # --- Step 2: Extract and Parse WBT file ---
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
        return {"passed": False, "score": 0, "feedback": "Failed to read the .wbt file from the container."}

    # --- Step 3: Evaluate All Four Wheel Joints ---
    axis_score_per_joint = 30.0 / len(joints)
    spring_score_per_joint = 30.0 / len(joints)
    damping_score_per_joint = 30.0 / len(joints)
    
    successful_axis_count = 0
    successful_spring_count = 0
    successful_damping_count = 0
    
    for joint_name in joints:
        params = extract_joint_params(wbt_content, joint_name)
        
        if not params:
            feedback_parts.append(f"Could not find HingeJointParameters for {joint_name}.")
            continue
            
        # Anti-Gaming check: Ensure standard axis hasn't been corrupted
        actual_rot_axis = params.get('axis', [0,0,0])
        if actual_rot_axis != starting_axis:
            feedback_parts.append(f"{joint_name} rotational 'axis' was incorrectly modified (expected {starting_axis}, got {actual_rot_axis}).")
            
        # Check suspensionAxis
        actual_susp_axis = params.get('suspensionAxis', [1.0, 0.0, 0.0])  # defaults to 1 0 0 in Webots if omitted
        if actual_susp_axis == exp_axis:
            score += axis_score_per_joint
            successful_axis_count += 1
            
        # Check suspensionSpringConstant
        actual_spring = params.get('spring', 0.0)
        if abs(actual_spring - exp_spring) <= spring_tol:
            score += spring_score_per_joint
            successful_spring_count += 1
            
        # Check suspensionDampingConstant
        actual_damping = params.get('damping', 0.0)
        if abs(actual_damping - exp_damping) <= damping_tol:
            score += damping_score_per_joint
            successful_damping_count += 1

    feedback_parts.append(f"Correct suspensionAxis: {successful_axis_count}/{len(joints)}")
    feedback_parts.append(f"Correct springConstant: {successful_spring_count}/{len(joints)}")
    feedback_parts.append(f"Correct dampingConstant: {successful_damping_count}/{len(joints)}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": round(score),
        "feedback": " | ".join(feedback_parts)
    }