#!/usr/bin/env python3
"""
Verifier for configure_humanoid_kinematics task.

A robotics engineer must configure the physics and kinematics of a bipedal robot:
1. basicTimeStep = 8
2. selfCollision = TRUE
3. LEFT_KNEE minStop=0.0, maxStop=2.5, dampingConstant=0.5
4. RIGHT_KNEE minStop=0.0, maxStop=2.5, dampingConstant=0.5

The verifier parses the structured Webots .wbt file to ensure nodes have the correct attributes.
"""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_block(text: str, def_name: str) -> str:
    """
    Extracts a VRML block starting from 'DEF {def_name}' up to its matching closing brace.
    """
    start_idx = text.find(f"DEF {def_name}")
    if start_idx == -1:
        return ""
    
    brace_idx = text.find("{", start_idx)
    if brace_idx == -1:
        return ""
        
    depth = 1
    for i in range(brace_idx + 1, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[start_idx:i+1]
    return ""


def check_knee_parameters(knee_block: str, expected_min: float, expected_max: float, expected_damping: float) -> tuple:
    """
    Checks if a HingeJoint block contains the correctly configured HingeJointParameters.
    Returns (success_bool, list_of_feedback_messages).
    """
    feedback = []
    success = True
    
    if not knee_block:
        return False, ["Knee DEF block not found."]
        
    # Extract HingeJointParameters sub-block
    param_idx = knee_block.find("HingeJointParameters")
    if param_idx == -1:
        return False, ["HingeJointParameters not found in knee block."]
        
    brace_idx = knee_block.find("{", param_idx)
    if brace_idx == -1:
        return False, ["Malformed HingeJointParameters block."]
        
    depth = 1
    end_idx = -1
    for i in range(brace_idx + 1, len(knee_block)):
        if knee_block[i] == '{':
            depth += 1
        elif knee_block[i] == '}':
            depth -= 1
            if depth == 0:
                end_idx = i
                break
                
    if end_idx == -1:
        return False, ["Unclosed HingeJointParameters block."]
        
    param_block = knee_block[param_idx:end_idx+1]
    
    # Check specific fields
    min_match = re.search(r'minStop\s+([\d.-]+)', param_block)
    max_match = re.search(r'maxStop\s+([\d.-]+)', param_block)
    damping_match = re.search(r'dampingConstant\s+([\d.-]+)', param_block)
    
    if min_match and float(min_match.group(1)) == expected_min:
        feedback.append(f"minStop correctly set to {expected_min}.")
    else:
        success = False
        actual = min_match.group(1) if min_match else "Missing"
        feedback.append(f"minStop incorrect. Expected {expected_min}, got {actual}.")
        
    if max_match and float(max_match.group(1)) == expected_max:
        feedback.append(f"maxStop correctly set to {expected_max}.")
    else:
        success = False
        actual = max_match.group(1) if max_match else "Missing"
        feedback.append(f"maxStop incorrect. Expected {expected_max}, got {actual}.")
        
    if damping_match and float(damping_match.group(1)) == expected_damping:
        feedback.append(f"dampingConstant correctly set to {expected_damping}.")
    else:
        success = False
        actual = damping_match.group(1) if damping_match else "Missing"
        feedback.append(f"dampingConstant incorrect. Expected {expected_damping}, got {actual}.")
        
    return success, feedback


def verify_configure_humanoid_kinematics(traj, env_info, task_info):
    """
    Verify the biped_kinematics.wbt file has been correctly modified and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Desktop/biped_kinematics.wbt')
    expected_timestep = metadata.get('expected_timestep', 8)
    expected_minstop = metadata.get('expected_minstop', 0.0)
    expected_maxstop = metadata.get('expected_maxstop', 2.5)
    expected_damping = metadata.get('expected_damping', 0.5)

    score = 0
    feedback_parts = []
    
    # 1. Check basic task execution from exported JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Target file {expected_path} was not found. Ensure you save using File > Save World As."
        }
        
    if not result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it might not have been newly modified during task.")
        
    score += 10
    feedback_parts.append("File successfully saved.")

    # 2. Parse the saved WBT file
    temp_wbt = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_content = ""
    try:
        copy_from_env(expected_path, temp_wbt.name)
        with open(temp_wbt.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read exported world file: {e}"}
    finally:
        if os.path.exists(temp_wbt.name):
            os.unlink(temp_wbt.name)
            
    # Check 1: basicTimeStep
    worldinfo_idx = wbt_content.find('WorldInfo')
    if worldinfo_idx != -1:
        worldinfo_block = wbt_content[worldinfo_idx:worldinfo_idx+500]
        timestep_match = re.search(r'basicTimeStep\s+([\d.]+)', worldinfo_block)
        if timestep_match and float(timestep_match.group(1)) == expected_timestep:
            score += 20
            feedback_parts.append(f"basicTimeStep correctly set to {expected_timestep}.")
        else:
            actual = timestep_match.group(1) if timestep_match else "Missing"
            feedback_parts.append(f"basicTimeStep incorrect. Expected {expected_timestep}, got {actual}.")
    else:
        feedback_parts.append("WorldInfo node not found.")

    # Check 2: selfCollision
    biped_block = extract_block(wbt_content, metadata.get('robot_def', 'BIPED_ROBOT'))
    if biped_block:
        collision_match = re.search(r'selfCollision\s+(TRUE|FALSE)', biped_block)
        if collision_match and collision_match.group(1) == "TRUE":
            score += 20
            feedback_parts.append("BIPED_ROBOT selfCollision correctly set to TRUE.")
        else:
            actual = collision_match.group(1) if collision_match else "Missing"
            feedback_parts.append(f"BIPED_ROBOT selfCollision incorrect. Expected TRUE, got {actual}.")
    else:
        feedback_parts.append("BIPED_ROBOT definition not found.")

    # Check 3: LEFT_KNEE
    left_knee_block = extract_block(wbt_content, metadata.get('left_knee_def', 'LEFT_KNEE'))
    lk_success, lk_feedback = check_knee_parameters(left_knee_block, expected_minstop, expected_maxstop, expected_damping)
    if lk_success:
        score += 25
        feedback_parts.append("LEFT_KNEE correctly configured.")
    else:
        feedback_parts.append("LEFT_KNEE errors: " + "; ".join(lk_feedback))

    # Check 4: RIGHT_KNEE
    right_knee_block = extract_block(wbt_content, metadata.get('right_knee_def', 'RIGHT_KNEE'))
    rk_success, rk_feedback = check_knee_parameters(right_knee_block, expected_minstop, expected_maxstop, expected_damping)
    if rk_success:
        score += 25
        feedback_parts.append("RIGHT_KNEE correctly configured.")
    else:
        feedback_parts.append("RIGHT_KNEE errors: " + "; ".join(rk_feedback))

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }