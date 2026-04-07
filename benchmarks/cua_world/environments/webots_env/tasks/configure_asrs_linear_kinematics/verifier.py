#!/usr/bin/env python3
"""
Verifier for configure_asrs_linear_kinematics task.

Evaluates Webots .wbt syntax to ensure:
1. File exists and was saved properly.
2. X, Y, and Z joints maintain structural nesting.
3. minStop, maxStop, and maxVelocity are properly configured for each axis.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_block(text: str, start_idx: int) -> str:
    """Extracts a matching braced block starting at or after start_idx."""
    brace_start = text.find('{', start_idx)
    if brace_start == -1:
        return ""
    
    depth = 1
    for i in range(brace_start + 1, len(text)):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[start_idx:i+1]
    return ""


def extract_value(pattern: str, text: str) -> float:
    """Extracts a numerical value based on regex pattern."""
    match = re.search(pattern, text)
    if match:
        try:
            return float(match.group(1))
        except ValueError:
            pass
    return None


def verify_asrs_kinematics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    expected_cfg = metadata.get('expected', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/asrs_configured.wbt')

    score = 0
    feedback = []

    # 1. Check export result JSON
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        result_data = {"file_exists": False}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    if not result_data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": f"Target file {output_path} not found. Ensure you saved using File > Save World As."}

    # 2. Extract and parse the actual WBT file
    wbt_file_path = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt').name
    wbt_content = ""
    try:
        copy_from_env(output_path, wbt_file_path)
        with open(wbt_file_path, 'r', encoding='utf-8', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.error(f"Failed to copy wbt file: {e}")
    finally:
        if os.path.exists(wbt_file_path):
            os.unlink(wbt_file_path)

    if not wbt_content or "SliderJoint" not in wbt_content:
        return {"passed": False, "score": 0, "feedback": "Saved world file is empty or corrupted."}

    score += 10
    feedback.append("World file successfully saved.")

    # 3. Parse Structural Hierarchy & Values
    x_idx = wbt_content.find("DEF X_AXIS_JOINT")
    if x_idx == -1:
        return {"passed": False, "score": score, "feedback": "DEF X_AXIS_JOINT not found. Do not rename the joints."}
    
    x_block = extract_block(wbt_content, x_idx)

    # Validate nesting (Y inside X, Z inside Y)
    y_idx = x_block.find("DEF Y_AXIS_JOINT")
    if y_idx == -1:
        return {"passed": False, "score": score, "feedback": "Structural error: Y_AXIS_JOINT is no longer nested inside X_AXIS_JOINT."}
    
    y_block = extract_block(x_block, y_idx)

    z_idx = y_block.find("DEF Z_AXIS_JOINT")
    if z_idx == -1:
        return {"passed": False, "score": score, "feedback": "Structural error: Z_AXIS_JOINT is no longer nested inside Y_AXIS_JOINT."}
    
    z_block = extract_block(y_block, z_idx)

    # Verification map (block, criteria)
    blocks = {
        "X_AXIS_JOINT": {"block": x_block, "pts": (10, 10)}, # limits, speed
        "Y_AXIS_JOINT": {"block": y_block, "pts": (15, 15)},
        "Z_AXIS_JOINT": {"block": z_block, "pts": (20, 20)}
    }

    axes_passed = 0

    for axis_name, data in blocks.items():
        block_text = data["block"]
        pts_lim, pts_vel = data["pts"]
        expected = expected_cfg.get(axis_name, {})

        # Extract limits from JointParameters
        jp_idx = block_text.find("JointParameters")
        if jp_idx != -1:
            jp_block = extract_block(block_text, jp_idx)
            min_stop = extract_value(r'minStop\s+([-\d.]+)', jp_block)
            max_stop = extract_value(r'maxStop\s+([-\d.]+)', jp_block)
        else:
            min_stop, max_stop = None, None

        # Extract maxVelocity from LinearMotor
        lm_idx = block_text.find("LinearMotor")
        if lm_idx != -1:
            lm_block = extract_block(block_text, lm_idx)
            max_vel = extract_value(r'maxVelocity\s+([-\d.]+)', lm_block)
        else:
            max_vel = None

        axis_ok = True

        # Evaluate Limits
        if min_stop == expected.get('minStop') and max_stop == expected.get('maxStop'):
            score += pts_lim
            feedback.append(f"{axis_name} limits correct ({min_stop} to {max_stop}).")
        else:
            axis_ok = False
            feedback.append(f"{axis_name} limits incorrect. Expected [{expected.get('minStop')}, {expected.get('maxStop')}], got [{min_stop}, {max_stop}].")

        # Evaluate Velocity
        if max_vel == expected.get('maxVelocity'):
            score += pts_vel
            feedback.append(f"{axis_name} maxVelocity correct ({max_vel}).")
        else:
            axis_ok = False
            feedback.append(f"{axis_name} maxVelocity incorrect. Expected {expected.get('maxVelocity')}, got {max_vel}.")

        if axis_ok:
            axes_passed += 1

    passed = score >= 70 and axes_passed >= 2

    if passed:
        feedback.insert(0, "SUCCESS: Required configurations applied successfully.")
    else:
        feedback.insert(0, "FAIL: Configuration criteria not met.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }