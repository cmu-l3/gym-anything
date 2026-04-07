#!/usr/bin/env python3
"""
Verifier for configure_agricultural_rtk_gps task.

A field robotics engineer must configure WorldInfo georeferencing and GPS accuracy
for a vineyard autonomous tractor simulation.

Scoring (100 points total):
  - File saved at correct path and created during task: 10 points
  - WorldInfo gpsCoordinateSystem set to "WGS84": 25 points
  - WorldInfo gpsReference set to 38.281 -122.278 25.5: 25 points
  - WorldInfo northDirection set to 0 1 0: 20 points
  - GPS node accuracy set to 0.02: 20 points

Pass threshold: 75 points and the file must be successfully exported.
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_agricultural_rtk_gps(traj, env_info, task_info):
    """
    Verify that the georeferencing parameters and GPS sensor accuracy are correct.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/vineyard_georeferenced.wbt')
    
    expected_gps_coordinate_system = metadata.get('expected_gps_coordinate_system', 'WGS84')
    expected_accuracy = metadata.get('expected_gps_accuracy', 0.02)

    score = 0
    feedback_parts = []

    # --- Read export script result ---
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    
    file_exists = False
    file_created_during_task = False
    
    try:
        copy_from_env('/tmp/task_result.json', result_file.name)
        with open(result_file.name, 'r') as f:
            export_result = json.load(f)
            file_exists = export_result.get('file_exists', False)
            file_created_during_task = export_result.get('file_created_during_task', False)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Failed to read task_result.json: {e}")
        try:
            os.unlink(result_file.name)
        except Exception:
            pass

    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }

    # --- Copy the actual .wbt file ---
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

    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but is empty or invalid."
        }

    score += 10
    if file_created_during_task:
        feedback_parts.append("World file saved at correct path during task execution")
    else:
        feedback_parts.append("World file exists at correct path")

    # --- Check gpsCoordinateSystem ---
    system_match = re.search(r'gpsCoordinateSystem\s+"([^"]+)"', wbt_content)
    if system_match:
        actual_system = system_match.group(1)
        if actual_system == expected_gps_coordinate_system:
            score += 25
            feedback_parts.append(f"gpsCoordinateSystem correctly set to {expected_gps_coordinate_system}")
        else:
            feedback_parts.append(f"gpsCoordinateSystem is '{actual_system}', expected '{expected_gps_coordinate_system}'")
    else:
        feedback_parts.append("gpsCoordinateSystem field not found in saved world")

    # --- Check gpsReference ---
    # Matches 'gpsReference 38.281 -122.278 25.5'
    reference_match = re.search(r'gpsReference\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
    if reference_match:
        lat = float(reference_match.group(1))
        lon = float(reference_match.group(2))
        alt = float(reference_match.group(3))
        
        # Check against 38.281, -122.278, 25.5
        if abs(lat - 38.281) < 0.001 and abs(lon - -122.278) < 0.001 and abs(alt - 25.5) < 0.1:
            score += 25
            feedback_parts.append("gpsReference correctly set to vineyard coordinates")
        else:
            feedback_parts.append(f"gpsReference is {lat} {lon} {alt}, expected 38.281 -122.278 25.5")
    else:
        feedback_parts.append("gpsReference field not found or malformed")

    # --- Check northDirection ---
    # Matches 'northDirection 0 1 0'
    north_match = re.search(r'northDirection\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
    if north_match:
        x = float(north_match.group(1))
        y = float(north_match.group(2))
        z = float(north_match.group(3))
        
        if abs(x - 0) < 0.01 and abs(y - 1) < 0.01 and abs(z - 0) < 0.01:
            score += 20
            feedback_parts.append("northDirection correctly set to 0 1 0")
        else:
            feedback_parts.append(f"northDirection is {x} {y} {z}, expected 0 1 0")
    else:
        feedback_parts.append("northDirection field not found or malformed")

    # --- Check GPS accuracy ---
    # To be robust, find the accuracy field within or near the GPS node
    # Sinc 'accuracy' might just appear directly under 'DEF rtk_gps GPS {'
    gps_idx = wbt_content.find('rtk_gps')
    if gps_idx != -1:
        # Search the chunk of text immediately following the GPS definition
        gps_chunk = wbt_content[gps_idx:gps_idx+300]
        acc_match = re.search(r'accuracy\s+([\d.]+)', gps_chunk)
        if acc_match:
            actual_acc = float(acc_match.group(1))
            if abs(actual_acc - expected_accuracy) < 0.001:
                score += 20
                feedback_parts.append(f"GPS accuracy correctly set to {expected_accuracy}")
            else:
                feedback_parts.append(f"GPS accuracy is {actual_acc}, expected {expected_accuracy}")
        else:
            feedback_parts.append("GPS accuracy field not found within GPS node")
    else:
        feedback_parts.append("GPS node 'rtk_gps' not found in saved world")

    # --- Final determination ---
    passed = score >= 75 and file_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }