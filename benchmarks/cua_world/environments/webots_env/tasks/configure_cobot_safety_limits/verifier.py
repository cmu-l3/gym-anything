#!/usr/bin/env python3
"""
Verifier for configure_cobot_safety_limits task.

Requires the agent to configure collaborative safety limits in Webots:
1. Base Joint: minStop = -1.5708, maxStop = 1.5708, maxVelocity = 1.57
2. Shoulder Joint: minStop = -0.7854, maxStop = 1.5708, maxVelocity = 1.57

Uses robust block-parsing to isolate the properties of each joint to ensure
modifications were applied to the correct HingeJointParameters and RotationalMotor.
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def extract_node_block(content: str, def_name: str) -> str:
    """
    Extracts the full text block of a VRML node given its DEF name, 
    matching nested braces correctly.
    """
    idx = content.find(f"DEF {def_name}")
    if idx == -1:
        return None
        
    start_brace = content.find("{", idx)
    if start_brace == -1:
        return None
        
    depth = 1
    i = start_brace + 1
    while i < len(content) and depth > 0:
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
        i += 1
        
    return content[idx:i]


def check_value(block: str, param_name: str, expected_val: float, tolerance: float) -> tuple:
    """Finds a parameter in a VRML block and checks if it's within tolerance."""
    if not block:
        return False, "Node block missing"
        
    match = re.search(rf'{param_name}\s+([-\d.]+)', block)
    if not match:
        return False, f"'{param_name}' not found"
        
    actual_val = float(match.group(1))
    if abs(actual_val - expected_val) <= tolerance:
        return True, f"{param_name}={actual_val} (Correct)"
    else:
        return False, f"{param_name}={actual_val} (Expected {expected_val})"


def verify_configure_cobot_safety_limits(traj, env_info, task_info):
    """
    Verify that the cobot's safety parameters were correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/safe_cobot.wbt')
    tol = metadata.get('tolerance', 0.01)

    score = 0
    feedback_parts = []
    
    # 1. Read export summary JSON
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_cobot_safety_limits_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {"file_exists": False}

    # 2. Check File Existence & Temporal Integrity
    if not export_result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world via File > Save World As."
        }
    
    if export_result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File correctly saved during task")
    else:
        feedback_parts.append("Warning: File timestamp predates task start (might be an old save)")

    # 3. Independently copy and parse the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file from VM: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass
            
    if not wbt_content:
        return {
            "passed": False,
            "score": score,
            "feedback": "Failed to read the saved world file."
        }

    # Extract isolated blocks for robust parsing
    base_block = extract_node_block(wbt_content, "BASE_JOINT")
    shoulder_block = extract_node_block(wbt_content, "SHOULDER_JOINT")
    
    # --- BASE JOINT VERIFICATION (45 points) ---
    if base_block:
        # Check minStop
        ok_bmin, msg_bmin = check_value(base_block, "minStop", metadata['base_min_stop'], tol)
        if ok_bmin: score += 15
        feedback_parts.append(f"Base minStop: {msg_bmin}")
        
        # Check maxStop
        ok_bmax, msg_bmax = check_value(base_block, "maxStop", metadata['base_max_stop'], tol)
        if ok_bmax: score += 15
        feedback_parts.append(f"Base maxStop: {msg_bmax}")
        
        # Check maxVelocity
        ok_bvel, msg_bvel = check_value(base_block, "maxVelocity", metadata['base_max_vel'], tol)
        if ok_bvel: score += 15
        feedback_parts.append(f"Base maxVelocity: {msg_bvel}")
    else:
        feedback_parts.append("DEF BASE_JOINT not found or corrupted in world file.")

    # --- SHOULDER JOINT VERIFICATION (45 points) ---
    if shoulder_block:
        # Check minStop
        ok_smin, msg_smin = check_value(shoulder_block, "minStop", metadata['shoulder_min_stop'], tol)
        if ok_smin: score += 15
        feedback_parts.append(f"Shoulder minStop: {msg_smin}")
        
        # Check maxStop
        ok_smax, msg_smax = check_value(shoulder_block, "maxStop", metadata['shoulder_max_stop'], tol)
        if ok_smax: score += 15
        feedback_parts.append(f"Shoulder maxStop: {msg_smax}")
        
        # Check maxVelocity
        ok_svel, msg_svel = check_value(shoulder_block, "maxVelocity", metadata['shoulder_max_vel'], tol)
        if ok_svel: score += 15
        feedback_parts.append(f"Shoulder maxVelocity: {msg_svel}")
    else:
        feedback_parts.append("DEF SHOULDER_JOINT not found or corrupted in world file.")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }