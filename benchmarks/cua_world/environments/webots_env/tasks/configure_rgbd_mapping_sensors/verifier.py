#!/usr/bin/env python3
"""
Verifier for configure_rgbd_mapping_sensors task.

A perception engineer must reconfigure an RGB-D sensor suite on a mobile robot
to match the hardware specifications of an Intel RealSense D435 camera, and ensure
the two sensors are co-located for accurate depth-color registration.

Scoring (100 points total):
  - File exists and was saved correctly: 5 points
  - Depth camera (RangeFinder) width & height: 20 points (10 + 10)
  - Depth camera maxRange & minRange: 25 points (15 + 10)
  - Depth camera FOV: 10 points
  - RGB camera (Camera) width & height: 20 points (10 + 10)
  - RGB camera FOV: 10 points
  - Sensors co-located (distance < 0.01m): 10 points

Pass threshold: 70 points
"""

import json
import re
import math
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_sensor_block(content: str, sensor_name: str) -> str:
    """Safely extract the VRML block associated with a named node."""
    idx = content.find(f'name "{sensor_name}"')
    if idx == -1:
        return ""
    
    # Find the start of the node (usually the closest '{' before the name)
    start_idx = content.rfind('{', 0, idx)
    if start_idx == -1:
        start_idx = max(0, idx - 100)
        
    # Find the matching closing brace
    depth = 1
    end_idx = start_idx
    for i in range(start_idx + 1, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
            if depth == 0:
                end_idx = i
                break
                
    return content[start_idx:end_idx+1]

def verify_configure_rgbd_sensors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/rgbd_mapping_robot.wbt')
    
    # Expected values
    exp_d_w, exp_d_h = metadata.get('depth_width', 640), metadata.get('depth_height', 480)
    exp_d_max, exp_d_min = metadata.get('depth_maxrange', 10.0), metadata.get('depth_minrange', 0.3)
    exp_d_fov = metadata.get('depth_fov', 1.5184)
    exp_c_w, exp_c_h = metadata.get('rgb_width', 640), metadata.get('rgb_height', 480)
    exp_c_fov = metadata.get('rgb_fov', 1.2040)

    score = 0
    feedback_parts = []
    
    # Check basic task result metadata for gaming prevention
    try:
        res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        res_file.close()
        copy_from_env('/tmp/task_result.json', res_file.name)
        with open(res_file.name) as f:
            export_result = json.load(f)
        os.unlink(res_file.name)
        
        if not export_result.get("file_created_during_task", False) and export_result.get("file_exists", False):
            return {"passed": False, "score": 0, "feedback": "Anti-gaming: File was not created/modified during the task run."}
    except Exception as e:
        logger.warning(f"Failed to read export JSON: {e}")

    # Independently copy and parse the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

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

    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Ensure you use File > Save World As."
        }

    score += 5
    feedback_parts.append("File saved correctly")

    # Extract Depth Sensor (RangeFinder)
    depth_block = extract_sensor_block(wbt_content, "depth_camera")
    rgb_block = extract_sensor_block(wbt_content, "rgb_camera")

    if not depth_block:
        feedback_parts.append("Could not find 'depth_camera' node in saved world")
    else:
        # Depth Width
        m_dw = re.search(r'width\s+(\d+)', depth_block)
        if m_dw and int(m_dw.group(1)) == exp_d_w:
            score += 10
            feedback_parts.append(f"Depth width set to {exp_d_w}")
        else:
            actual = m_dw.group(1) if m_dw else "Not found"
            feedback_parts.append(f"Depth width: expected {exp_d_w}, got {actual}")

        # Depth Height
        m_dh = re.search(r'height\s+(\d+)', depth_block)
        if m_dh and int(m_dh.group(1)) == exp_d_h:
            score += 10
            feedback_parts.append(f"Depth height set to {exp_d_h}")
        else:
            actual = m_dh.group(1) if m_dh else "Not found"
            feedback_parts.append(f"Depth height: expected {exp_d_h}, got {actual}")

        # Depth maxRange
        m_dmax = re.search(r'maxRange\s+([\d.]+)', depth_block)
        if m_dmax and abs(float(m_dmax.group(1)) - exp_d_max) <= 2.0:
            score += 15
            feedback_parts.append(f"Depth maxRange correct (~{exp_d_max}m)")
        else:
            actual = m_dmax.group(1) if m_dmax else "Not found"
            feedback_parts.append(f"Depth maxRange: expected {exp_d_max}, got {actual}")

        # Depth minRange
        m_dmin = re.search(r'minRange\s+([\d.]+)', depth_block)
        if m_dmin and abs(float(m_dmin.group(1)) - exp_d_min) <= 0.1:
            score += 10
            feedback_parts.append(f"Depth minRange correct (~{exp_d_min}m)")
        else:
            actual = m_dmin.group(1) if m_dmin else "Not found"
            feedback_parts.append(f"Depth minRange: expected {exp_d_min}, got {actual}")

        # Depth FOV
        m_dfov = re.search(r'fieldOfView\s+([\d.]+)', depth_block)
        if m_dfov and abs(float(m_dfov.group(1)) - exp_d_fov) <= 0.2:
            score += 10
            feedback_parts.append("Depth FOV correct")
        else:
            actual = m_dfov.group(1) if m_dfov else "Not found"
            feedback_parts.append(f"Depth FOV: expected {exp_d_fov}, got {actual}")

    if not rgb_block:
        feedback_parts.append("Could not find 'rgb_camera' node in saved world")
    else:
        # RGB Width
        m_cw = re.search(r'width\s+(\d+)', rgb_block)
        if m_cw and int(m_cw.group(1)) == exp_c_w:
            score += 10
            feedback_parts.append(f"RGB width set to {exp_c_w}")
        else:
            actual = m_cw.group(1) if m_cw else "Not found"
            feedback_parts.append(f"RGB width: expected {exp_c_w}, got {actual}")

        # RGB Height
        m_ch = re.search(r'height\s+(\d+)', rgb_block)
        if m_ch and int(m_ch.group(1)) == exp_c_h:
            score += 10
            feedback_parts.append(f"RGB height set to {exp_c_h}")
        else:
            actual = m_ch.group(1) if m_ch else "Not found"
            feedback_parts.append(f"RGB height: expected {exp_c_h}, got {actual}")

        # RGB FOV
        m_cfov = re.search(r'fieldOfView\s+([\d.]+)', rgb_block)
        if m_cfov and abs(float(m_cfov.group(1)) - exp_c_fov) <= 0.2:
            score += 10
            feedback_parts.append("RGB FOV correct")
        else:
            actual = m_cfov.group(1) if m_cfov else "Not found"
            feedback_parts.append(f"RGB FOV: expected {exp_c_fov}, got {actual}")

    # Check Co-location (Translations must match)
    if depth_block and rgb_block:
        trans_d = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', depth_block)
        trans_c = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', rgb_block)
        
        if trans_d and trans_c:
            t_d = [float(trans_d.group(1)), float(trans_d.group(2)), float(trans_d.group(3))]
            t_c = [float(trans_c.group(1)), float(trans_c.group(2)), float(trans_c.group(3))]
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(t_d, t_c)))
            
            if dist < 0.01:
                score += 10
                feedback_parts.append("Sensors perfectly co-located")
            else:
                feedback_parts.append(f"Sensors NOT co-located (distance: {dist:.3f}m). rgb_camera must share depth_camera's position.")
        else:
            feedback_parts.append("Translation fields missing from one or both sensors")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }