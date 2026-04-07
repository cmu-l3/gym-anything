#!/usr/bin/env python3
"""
Verifier for configure_ncap_pedestrian_aeb task.

An ADAS validation engineer must configure a pedestrian dummy and camera sensor for
an AEB test protocol.

Scoring (100 points total):
  - File saved at correct path during task window: 10 points
  - Pedestrian speed = 1.5: 15 points
  - Pedestrian shirtColor = 1 0.5 0: 20 points
  - Pedestrian trajectory has correct waypoints: 25 points
  - Camera recognition node added: 30 points

Pass threshold: 75 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_ncap_pedestrian_aeb(traj, env_info, task_info):
    """
    Verify the NCAP scenario world was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/ncap_aeb_configured.wbt')
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: Read export result JSON for anti-gaming checks ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/ncap_aeb_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Failed to read JSON result: {e}")
        export_result = {}

    file_created_during_task = export_result.get("file_created_during_task", False)

    # --- Step 2: Copy and parse the .wbt file independently ---
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

    # --- Criterion 1: Check file existence and anti-gaming ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Ensure you save using File > Save World As."
        }
        
    if not file_created_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file timestamp predates task start. You must actively save the file during the task."
        }

    score += 10
    feedback_parts.append("World file saved correctly")

    # --- Narrow search scope to Pedestrian and Camera to avoid false positives ---
    pedestrian_idx = wbt_content.find('NCAP_TARGET Pedestrian')
    if pedestrian_idx == -1:
        pedestrian_idx = 0
    pedestrian_block = wbt_content[pedestrian_idx:pedestrian_idx+1000]

    camera_idx = wbt_content.find('front_camera Camera')
    if camera_idx == -1:
        camera_idx = 0
    camera_block = wbt_content[camera_idx:camera_idx+500]

    # --- Criterion 2: Pedestrian Speed (15 points) ---
    speed_match = re.search(r'speed\s+([\d.]+)', pedestrian_block)
    if speed_match:
        actual_speed = float(speed_match.group(1))
        if abs(actual_speed - 1.5) < 0.01:
            score += 15
            feedback_parts.append("Pedestrian speed correct (1.5 m/s)")
        else:
            feedback_parts.append(f"Pedestrian speed is {actual_speed}, expected 1.5")
    else:
        feedback_parts.append("Pedestrian speed field not found")

    # --- Criterion 3: Pedestrian shirtColor (20 points) ---
    color_match = re.search(r'shirtColor\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', pedestrian_block)
    if color_match:
        r, g, b = float(color_match.group(1)), float(color_match.group(2)), float(color_match.group(3))
        if abs(r - 1.0) < 0.05 and abs(g - 0.5) < 0.05 and abs(b - 0.0) < 0.05:
            score += 20
            feedback_parts.append("Pedestrian shirtColor correct (High-Vis Orange)")
        else:
            feedback_parts.append(f"Pedestrian shirtColor is {r} {g} {b}, expected 1 0.5 0")
    else:
        feedback_parts.append("Pedestrian shirtColor field not found")

    # --- Criterion 4: Pedestrian Trajectory (25 points) ---
    traj_match = re.search(r'trajectory\s*\[(.*?)\]', pedestrian_block, re.DOTALL)
    if traj_match:
        traj_content = traj_match.group(1)
        # Extract all numeric values
        nums = re.findall(r'[-+]?\d*\.?\d+', traj_content)
        floats = [float(n) for n in nums]
        
        # We expect two waypoints: 0 0 0 and 0 -6 0 (6 floats total)
        if len(floats) >= 6:
            p1 = floats[0:3]
            p2 = floats[3:6]
            if (abs(p1[0]-0) < 0.01 and abs(p1[1]-0) < 0.01 and abs(p1[2]-0) < 0.01 and
                abs(p2[0]-0) < 0.01 and abs(p2[1]+6) < 0.01 and abs(p2[2]-0) < 0.01):
                score += 25
                feedback_parts.append("Pedestrian trajectory waypoints correct")
            else:
                feedback_parts.append(f"Trajectory waypoints incorrect. Found: {p1}, {p2}")
        else:
            feedback_parts.append(f"Trajectory incomplete. Expected 2 waypoints, found {len(floats)//3}")
    else:
        feedback_parts.append("Pedestrian trajectory field not found or empty")

    # --- Criterion 5: Camera Recognition Node (30 points) ---
    # Check if 'recognition Recognition' exists inside the camera block
    has_recognition = bool(re.search(r'recognition\s+Recognition', camera_block))
    if has_recognition:
        score += 30
        feedback_parts.append("Camera recognition node enabled")
    else:
        feedback_parts.append("Camera recognition node is missing or still NULL")

    # Calculate final status
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }