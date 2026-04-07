#!/usr/bin/env python3
"""
Verifier for configure_slam_sensor_noise task.

Verifies that a SLAM engineer agent successfully modified the resolution and noise
parameters of 5 distinct sensors (2 encoders, 3 IRs) in a Webots world.

Scoring (100 points total):
  - File saved at correct path and created during task: 10 points
  - Left Encoder (18 pts: 9 resolution, 9 noise)
  - Right Encoder (18 pts: 9 resolution, 9 noise)
  - Front IR (18 pts: 9 resolution, 9 noise)
  - Left IR (18 pts: 9 resolution, 9 noise)
  - Right IR (18 pts: 9 resolution, 9 noise)

Pass threshold: 70 points (requires file save + at least 3 fully correct sensors + 1 partial)
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_sensor_blocks(content, node_type):
    """
    Robustly extract blocks of a specific Webots node type using brace matching.
    Returns a list of string blocks containing the internal fields of the node.
    """
    blocks = []
    # Find all occurrences of the node_type
    for match in re.finditer(rf'{node_type}\s*{{', content):
        start_idx = match.end() - 1 # Points to '{'
        brace_count = 0
        end_idx = -1
        
        for i in range(start_idx, len(content)):
            if content[i] == '{':
                brace_count += 1
            elif content[i] == '}':
                brace_count -= 1
                if brace_count == 0:
                    end_idx = i
                    break
        
        if end_idx != -1:
            blocks.append(content[start_idx+1:end_idx])
            
    return blocks

def evaluate_sensor(wbt_content, node_type, sensor_name, exp_res, exp_noise):
    """
    Extracts the block for the given sensor name and evaluates its resolution and noise.
    """
    blocks = extract_sensor_blocks(wbt_content, node_type)
    for block in blocks:
        # Check if this block is the target sensor
        name_match = re.search(r'name\s+"([^"]*)"', block)
        if name_match and name_match.group(1) == sensor_name:
            # Found the correct sensor block, now check properties
            res_match = re.search(r'resolution\s+([\d.]+)', block)
            noise_match = re.search(r'noise\s+([\d.]+)', block)
            
            res_val = float(res_match.group(1)) if res_match else None
            noise_val = float(noise_match.group(1)) if noise_match else None
            
            # Using strict equality with tiny tolerance for floating point representations
            res_ok = res_val is not None and abs(res_val - exp_res) < 0.00001
            noise_ok = noise_val is not None and abs(noise_val - exp_noise) < 0.00001
            
            return True, res_ok, noise_ok, res_val, noise_val
            
    return False, False, False, None, None

def verify_configure_slam_sensor_noise(traj, env_info, task_info):
    """
    Verify that the simulated SLAM sensors have been degraded correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/noisy_slam_test.wbt')
    
    exp_enc_res = metadata.get('expected_encoder_resolution', 0.0123)
    exp_enc_noise = metadata.get('expected_encoder_noise', 0.015)
    exp_ir_res = metadata.get('expected_ir_resolution', 0.002)
    exp_ir_noise = metadata.get('expected_ir_noise', 0.05)

    score = 0
    feedback_parts = []
    
    # 1. Evaluate task result JSON metadata
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    try:
        copy_from_env('/tmp/configure_slam_sensor_noise_result.json', result_file.name)
        with open(result_file.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {}

    if not export_result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Must use File > Save World As."
        }
        
    if not export_result.get("file_created_during_task", True):
        feedback_parts.append("WARNING: File timestamps indicate it may not have been saved during this task run.")
    else:
        score += 10
        feedback_parts.append("World file successfully saved.")

    # 2. Parse the WBT file
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
        except:
            pass
            
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Output file is empty or corrupted."
        }

    # 3. Evaluate each target sensor
    sensors_to_check = [
        ("left_encoder", "PositionSensor", exp_enc_res, exp_enc_noise),
        ("right_encoder", "PositionSensor", exp_enc_res, exp_enc_noise),
        ("ir_front", "DistanceSensor", exp_ir_res, exp_ir_noise),
        ("ir_left", "DistanceSensor", exp_ir_res, exp_ir_noise),
        ("ir_right", "DistanceSensor", exp_ir_res, exp_ir_noise)
    ]

    sensors_found = 0
    sensors_perfect = 0

    for name, node_type, e_res, e_noise in sensors_to_check:
        found, res_ok, noise_ok, actual_res, actual_noise = evaluate_sensor(
            wbt_content, node_type, name, e_res, e_noise
        )
        
        if not found:
            feedback_parts.append(f"Sensor '{name}' missing or renamed.")
            continue
            
        sensors_found += 1
        sensor_score = 0
        
        if res_ok:
            score += 9
            sensor_score += 9
        if noise_ok:
            score += 9
            sensor_score += 9
            
        if sensor_score == 18:
            sensors_perfect += 1
            feedback_parts.append(f"'{name}': Perfect (res={e_res}, noise={e_noise}).")
        else:
            feedback_parts.append(f"'{name}': Partial/Failed (res_ok={res_ok}, noise_ok={noise_ok}).")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "sensors_found": sensors_found,
            "sensors_perfect": sensors_perfect,
            "file_saved_ok": bool(score >= 10)
        }
    }