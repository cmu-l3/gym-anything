#!/usr/bin/env python3
"""
Verifier for configure_amr_social_navigation task.

An AMR social navigation test scenario needs to be configured:
- Pedestrian speed = 1.4
- Pedestrian trajectory = [5.0 2.5 0.0, 5.0 -2.5 0.0]
- Lidar translation Z = 0.4
- Lidar fieldOfView = 4.71
- Lidar horizontalResolution = 1080

Scoring (100 points total):
  - File exists and valid (modified during task): 10 points
  - Pedestrian Speed: 15 points
  - Pedestrian Trajectory: 25 points
  - Lidar Height: 20 points
  - Lidar FOV: 15 points
  - Lidar Resolution: 15 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def find_block_around(content, keyword, window_size=800):
    """Helper to extract a chunk of text around a keyword."""
    idx = content.find(keyword)
    if idx == -1:
        return ""
    start = max(0, idx - window_size)
    end = min(len(content), idx + window_size)
    return content[start:end]

def verify_configure_amr_social_navigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/amr_social_navigation.wbt')
    
    score = 0
    feedback_parts = []
    
    # 1. Read export metadata JSON
    result_meta = {}
    try:
        temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_meta.close()
        copy_from_env('/tmp/amr_social_navigation_result.json', temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
        os.unlink(temp_meta.name)
    except Exception as e:
        logger.warning(f"Could not load export metadata: {e}")

    # Check anti-gaming
    if not result_meta.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }
        
    if not result_meta.get('file_modified_during_task', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "File exists but was not modified during the task. You must make changes and save."
        }
        
    score += 10
    feedback_parts.append("File saved successfully")

    # 2. Extract and read the actual .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

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

    if len(wbt_content) < 100:
        return {
            "passed": False,
            "score": score,
            "feedback": "Saved world file is suspiciously small or empty."
        }

    # Extract relevant blocks for safer regex matching
    ped_block = find_block_around(wbt_content, "DEF DOCTOR Pedestrian")
    lidar_block = find_block_around(wbt_content, 'name "safety_lidar"')

    # --- Verify Pedestrian Speed ---
    speed_match = re.search(r'speed\s+([\d.]+)', ped_block)
    if speed_match:
        actual_speed = float(speed_match.group(1))
        if actual_speed == metadata.get('expected_speed', 1.4):
            score += 15
            feedback_parts.append(f"Pedestrian speed correctly set to {actual_speed}")
        else:
            feedback_parts.append(f"Pedestrian speed is {actual_speed}, expected 1.4")
    else:
        feedback_parts.append("Pedestrian speed field not found")

    # --- Verify Pedestrian Trajectory ---
    traj_match = re.search(r'trajectory\s*\[(.*?)\]', ped_block, re.DOTALL)
    if traj_match:
        traj_text = traj_match.group(1)
        # Verify point 1 (5 2.5 0)
        has_pt1 = bool(re.search(r'5(\.0*)?\s+2\.5(0*)?\s+0(\.0*)?', traj_text))
        # Verify point 2 (5 -2.5 0)
        has_pt2 = bool(re.search(r'5(\.0*)?\s+-2\.5(0*)?\s+0(\.0*)?', traj_text))
        
        if has_pt1 and has_pt2:
            score += 25
            feedback_parts.append("Pedestrian trajectory correctly configured")
        else:
            feedback_parts.append("Pedestrian trajectory array missing required specific waypoints")
    else:
        feedback_parts.append("Pedestrian trajectory list not found or empty")

    # --- Verify Lidar Height (Translation Z) ---
    trans_match = re.search(r'translation\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)', lidar_block)
    if trans_match:
        actual_z = float(trans_match.group(3))
        if actual_z == metadata.get('expected_lidar_z', 0.4):
            score += 20
            feedback_parts.append(f"Lidar translation Z correctly set to {actual_z}")
        else:
            feedback_parts.append(f"Lidar translation Z is {actual_z}, expected 0.4")
    else:
        feedback_parts.append("Lidar translation field not found")

    # --- Verify Lidar FOV ---
    fov_match = re.search(r'fieldOfView\s+([\d.]+)', lidar_block)
    if fov_match:
        actual_fov = float(fov_match.group(1))
        if actual_fov == metadata.get('expected_lidar_fov', 4.71):
            score += 15
            feedback_parts.append(f"Lidar FOV correctly set to {actual_fov}")
        else:
            feedback_parts.append(f"Lidar FOV is {actual_fov}, expected 4.71")
    else:
        feedback_parts.append("Lidar fieldOfView field not found")

    # --- Verify Lidar Resolution ---
    res_match = re.search(r'horizontalResolution\s+(\d+)', lidar_block)
    if res_match:
        actual_res = int(res_match.group(1))
        if actual_res == metadata.get('expected_lidar_res', 1080):
            score += 15
            feedback_parts.append(f"Lidar resolution correctly set to {actual_res}")
        else:
            feedback_parts.append(f"Lidar horizontalResolution is {actual_res}, expected 1080")
    else:
        feedback_parts.append("Lidar horizontalResolution field not found")

    # Final evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }