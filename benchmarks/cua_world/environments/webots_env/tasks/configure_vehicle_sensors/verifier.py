#!/usr/bin/env python3
"""
Verifier for configure_vehicle_sensors task.

An AV simulation engineer must reconfigure an autonomous vehicle's sensors to match
real hardware specifications (Velodyne VLP-16 LIDAR and standard automotive camera).

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Camera width = 640: 20 points
  - Camera height = 480: 20 points
  - Lidar numberOfLayers = 16: 25 points
  - Lidar maxRange = 100: 25 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_vehicle_sensors(traj, env_info, task_info):
    """
    Verify that the AV sensor configuration world has been saved with correct specs.
    Copies the .wbt file from the VM and checks for exact sensor parameter values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/av_sensors_configured.wbt')
    expected_cam_width = metadata.get('expected_camera_width', 640)
    expected_cam_height = metadata.get('expected_camera_height', 480)
    expected_lidar_layers = metadata.get('expected_lidar_layers', 16)
    expected_lidar_maxrange = metadata.get('expected_lidar_maxrange', 100)

    score = 0
    feedback_parts = []

    # --- Step 1: Try to get export result JSON for quick check ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_vehicle_sensors_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception:
        export_result = {}

    # --- Step 2: Independently copy and parse the .wbt file ---
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

    # --- Step 3: Check file existence ---
    file_exists = (wbt_content is not None and len(wbt_content) > 100)
    if file_exists:
        score += 10
        feedback_parts.append("World file saved at correct path")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. File must be saved using File > Save World As."
        }

    # --- Step 4: Check camera width ---
    # Search for width value near camera node
    # .wbt format: 'width NUMBER' — we look for the specific value
    cam_width_match = re.search(r'width\s+(\d+)', wbt_content)
    if cam_width_match:
        actual_width = int(cam_width_match.group(1))
        if actual_width == expected_cam_width:
            score += 20
            feedback_parts.append(f"Camera width correctly set to {expected_cam_width}")
        else:
            feedback_parts.append(
                f"Camera width is {actual_width}, expected {expected_cam_width}"
            )
    else:
        feedback_parts.append("Camera width field not found in saved world")

    # --- Step 5: Check camera height ---
    cam_height_match = re.search(r'height\s+(\d+)', wbt_content)
    if cam_height_match:
        actual_height = int(cam_height_match.group(1))
        if actual_height == expected_cam_height:
            score += 20
            feedback_parts.append(f"Camera height correctly set to {expected_cam_height}")
        else:
            feedback_parts.append(
                f"Camera height is {actual_height}, expected {expected_cam_height}"
            )
    else:
        feedback_parts.append("Camera height field not found in saved world")

    # --- Step 6: Check lidar numberOfLayers ---
    lidar_layers_match = re.search(r'numberOfLayers\s+(\d+)', wbt_content)
    if lidar_layers_match:
        actual_layers = int(lidar_layers_match.group(1))
        if actual_layers == expected_lidar_layers:
            score += 25
            feedback_parts.append(f"LIDAR numberOfLayers correctly set to {expected_lidar_layers}")
        else:
            feedback_parts.append(
                f"LIDAR numberOfLayers is {actual_layers}, expected {expected_lidar_layers} (Velodyne VLP-16 spec)"
            )
    else:
        feedback_parts.append("LIDAR numberOfLayers field not found in saved world")

    # --- Step 7: Check lidar maxRange ---
    lidar_range_matches = re.findall(r'maxRange\s+([\d.]+)', wbt_content)
    if lidar_range_matches:
        actual_range = float(lidar_range_matches[0])
        if abs(actual_range - expected_lidar_maxrange) < 1.0:
            score += 25
            feedback_parts.append(f"LIDAR maxRange correctly set to {expected_lidar_maxrange}m")
        else:
            feedback_parts.append(
                f"LIDAR maxRange is {actual_range}, expected {expected_lidar_maxrange} (Velodyne VLP-16 spec)"
            )
    else:
        feedback_parts.append("LIDAR maxRange field not found in saved world")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "debug": {
            "file_exists": file_exists,
            "wbt_size": len(wbt_content) if wbt_content else 0,
        }
    }
