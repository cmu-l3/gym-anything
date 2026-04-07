#!/usr/bin/env python3
"""
Verifier for configure_ir_sensor_lookup_table task.

Verifies:
1. File exists and was created during the task run (Anti-gaming).
2. The DistanceSensor 'type' field is 'infra-red'.
3. The DistanceSensor 'lookupTable' contains exactly 4 coordinate triplets.
4. The numeric values of the lookupTable match the required calibration points.
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def parse_wbt_sensor(wbt_content, sensor_name):
    """
    Safely extract the type and lookupTable from a specific DistanceSensor in a .wbt file.
    """
    parts = wbt_content.split('DistanceSensor {')
    sensor_content = ""
    for p in parts[1:]:
        if f'name "{sensor_name}"' in p:
            sensor_content = p
            break
            
    if not sensor_content:
        return None, None
        
    # Extract type
    type_match = re.search(r'type\s+"([^"]+)"', sensor_content)
    sensor_type = type_match.group(1) if type_match else None
    
    # Extract lookupTable array
    # Webots format: lookupTable [ 0 1 0, 0.5 0.5 0 ]
    lookup_match = re.search(r'lookupTable\s*\[(.*?)\]', sensor_content, re.DOTALL)
    lookup_floats = []
    if lookup_match:
        array_content = lookup_match.group(1)
        # Find all numbers (ints, floats, negative/positive)
        number_strs = re.findall(r'[-+]?\d*\.\d+|[-+]?\d+', array_content)
        lookup_floats = [float(n) for n in number_strs]
        
    return sensor_type, lookup_floats

def verify_configure_ir_sensor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/micromouse_calibrated.wbt')
    expected_type = metadata.get('expected_type', 'infra-red')
    expected_table = metadata.get('expected_lookup_table', [])
    tolerances = metadata.get('tolerances', [0.005, 2.0, 0.01]) # dist, response, noise
    sensor_name = metadata.get('sensor_name', 'front_ir')

    score = 0
    feedback_parts = []

    # 1. Check basic export results and anti-gaming
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Target file not found at {output_path}."
        }
    if not result.get('file_created_during_task'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file exists but was not created/modified during this session (Anti-gaming)."
        }
        
    score += 10
    feedback_parts.append("File correctly saved")

    # 2. Copy and parse the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to copy wbt file: {e}"}
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    sensor_type, lookup_floats = parse_wbt_sensor(wbt_content, sensor_name)
    
    if sensor_type is None:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Could not find DistanceSensor named '{sensor_name}' in the saved world."
        }

    # 3. Verify 'type' field
    if sensor_type == expected_type:
        score += 10
        feedback_parts.append(f"Sensor type correctly set to '{expected_type}'")
    else:
        feedback_parts.append(f"Sensor type is '{sensor_type}', expected '{expected_type}'")

    # 4. Verify 'lookupTable' Array length
    if len(lookup_floats) == 12:  # 4 items * 3 values
        score += 20
        feedback_parts.append("lookupTable contains exactly 4 points (12 values)")
    else:
        num_points = len(lookup_floats) // 3
        feedback_parts.append(f"lookupTable has {num_points} points ({len(lookup_floats)} values), expected exactly 4 points.")

    # 5. Verify Calibration Point Values
    # We evaluate up to 4 points if they exist. Each correct point gives 15 points.
    actual_triplets = [lookup_floats[i:i+3] for i in range(0, len(lookup_floats), 3)]
    
    for i in range(min(len(expected_table), len(actual_triplets))):
        exp = expected_table[i]
        act = actual_triplets[i]
        
        if len(act) < 3:
            continue
            
        dist_ok = abs(exp[0] - act[0]) <= tolerances[0]
        resp_ok = abs(exp[1] - act[1]) <= tolerances[1]
        noise_ok = abs(exp[2] - act[2]) <= tolerances[2]
        
        if dist_ok and resp_ok and noise_ok:
            score += 15
            feedback_parts.append(f"Point {i+1} correct")
        else:
            feedback_parts.append(f"Point {i+1} mismatch: Got {act}, Expected {exp}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }