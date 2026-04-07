#!/usr/bin/env python3
import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_configure_assembly_force_sensor(traj, env_info, task_info):
    """
    Verify that the assembly press components (slider damping, motor force, and touch sensor values)
    have been correctly modified.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/assembly_press_configured.wbt')
    expected_damping = metadata.get('expected_damping', 50.0)
    expected_max_force = metadata.get('expected_max_force', 500.0)
    expected_type = metadata.get('expected_type', 'force')
    expected_resolution = metadata.get('expected_resolution', 0.1)

    score = 0
    feedback_parts = []

    # Try checking the exported JSON first
    try:
        res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        res_file.close()
        copy_from_env('/tmp/configure_assembly_force_sensor_result.json', res_file.name)
        with open(res_file.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(res_file.name)
        
        if not export_result.get("file_created_during_task", False):
            feedback_parts.append("Warning: Output file was not freshly created during this task window.")
    except Exception:
        pass

    # Independently copy the .wbt file
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

    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }

    score += 10
    feedback_parts.append("World file saved at correct path")

    # Check dampingConstant
    damping_match = re.search(r'dampingConstant\s+([\d.]+)', wbt_content)
    if damping_match:
        actual_damping = float(damping_match.group(1))
        if abs(actual_damping - expected_damping) < 0.01:
            score += 15
            feedback_parts.append(f"dampingConstant correctly set to {expected_damping}")
        else:
            feedback_parts.append(f"dampingConstant is {actual_damping}, expected {expected_damping}")
    else:
        feedback_parts.append("dampingConstant not found")

    # Check maxForce
    force_match = re.search(r'maxForce\s+([\d.]+)', wbt_content)
    if force_match:
        actual_force = float(force_match.group(1))
        if abs(actual_force - expected_max_force) < 0.01:
            score += 15
            feedback_parts.append(f"maxForce correctly set to {expected_max_force}")
        else:
            feedback_parts.append(f"maxForce is {actual_force}, expected {expected_max_force}")
    else:
        feedback_parts.append("maxForce not found")

    # Find TouchSensor block
    touch_sensor_idx = wbt_content.find('TouchSensor')
    if touch_sensor_idx != -1:
        ts_block = wbt_content[touch_sensor_idx:touch_sensor_idx+1000]
        
        # Check TouchSensor type
        type_match = re.search(r'type\s+"([^"]+)"', ts_block)
        if type_match:
            actual_type = type_match.group(1)
            if actual_type == expected_type:
                score += 20
                feedback_parts.append(f"TouchSensor type correctly set to '{expected_type}'")
            else:
                feedback_parts.append(f"TouchSensor type is '{actual_type}', expected '{expected_type}'")
        else:
            feedback_parts.append("TouchSensor type field not found")

        # Check TouchSensor resolution
        res_match = re.search(r'resolution\s+([\d.-]+)', ts_block)
        if res_match:
            actual_res = float(res_match.group(1))
            if abs(actual_res - expected_resolution) < 0.001:
                score += 20
                feedback_parts.append(f"TouchSensor resolution correctly set to {expected_resolution}")
            else:
                feedback_parts.append(f"TouchSensor resolution is {actual_res}, expected {expected_resolution}")
        else:
            feedback_parts.append("TouchSensor resolution field not found")

        # Check TouchSensor lookupTable
        # Supports space/comma-separated numbers format handling
        lookup_match = re.search(r'lookupTable\s+\[(.*?)\]', ts_block, re.DOTALL)
        if lookup_match:
            values_str = lookup_match.group(1).replace(',', ' ').split()
            values = [float(v) for v in values_str if v.strip()]
            
            # expected values list match: [0, 0, 0, 500, 500, 0]
            if len(values) == 6 and values[0] == 0 and values[1] == 0 and values[2] == 0 and values[3] == 500 and values[4] == 500 and values[5] == 0:
                score += 20
                feedback_parts.append("TouchSensor lookupTable correctly set to [ 0 0 0, 500 500 0 ]")
            else:
                feedback_parts.append(f"TouchSensor lookupTable has incorrect values: {values}")
        else:
            feedback_parts.append("TouchSensor lookupTable not found")
            
    else:
        feedback_parts.append("TouchSensor node not found in world")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }