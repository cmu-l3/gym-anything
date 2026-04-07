#!/usr/bin/env python3
"""
Verifier for configure_lunar_rover_power task.

A space robotics engineer must configure a lunar rover's power system and solar panel
sensor in Webots to match mission specifications.

Scoring (100 points total):
  - File exists and modified during task: 15 points
  - Battery capacity array configured correctly: 25 points
  - LightSensor rotation set to face upwards: 20 points
  - LightSensor fieldOfView set to 3.1415: 20 points
  - LightSensor lookupTable calibrated to solar constant: 20 points

Pass threshold: 75 points, AND file must be created/modified during task
"""

import json
import re
import tempfile
import os
import math
import logging

logger = logging.getLogger(__name__)


def verify_configure_lunar_rover_power(traj, env_info, task_info):
    """
    Verify the lunar rover world was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/lunar_power_sim.wbt')
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: Check Export Result for Anti-Gaming ---
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Failed to load export result: {e}")
        export_result = {}

    file_exists = export_result.get('file_exists', False)
    file_created = export_result.get('file_created_during_task', False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Did you save the world?"
        }
        
    if not file_created:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was not modified during the task duration. (Anti-gaming check failed)"
        }
        
    score += 15
    feedback_parts.append("File correctly created/saved during task")

    # --- Step 2: Copy the .wbt file independently ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.error(f"Could not copy .wbt file: {e}")
        return {"passed": False, "score": score, "feedback": f"Could not read .wbt file: {e}"}

    # --- Step 3: Verify Battery Configuration ---
    # Look for the battery field within the LUNAR_ROVER definition
    rover_idx = wbt_content.find('LUNAR_ROVER')
    if rover_idx != -1:
        rover_segment = wbt_content[rover_idx:rover_idx+2000]
        # Match battery array: e.g., battery [10000 36000 50] or battery [ 10000, 36000, 50 ]
        battery_match = re.search(r'battery\s*\[(.*?)\]', rover_segment)
        if battery_match:
            nums = re.findall(r'[\d.]+', battery_match.group(1))
            if len(nums) >= 3:
                vals = [float(n) for n in nums[:3]]
                # Expected: [10000.0, 36000.0, 50.0]
                if abs(vals[0] - 10000) < 1 and abs(vals[1] - 36000) < 1 and abs(vals[2] - 50) < 0.1:
                    score += 25
                    feedback_parts.append("Rover battery correctly configured")
                else:
                    feedback_parts.append(f"Battery values incorrect: got {vals}, expected [10000, 36000, 50]")
            else:
                feedback_parts.append(f"Battery array incomplete. Found: {battery_match.group(1)}")
        else:
            feedback_parts.append("Battery array field not found in LUNAR_ROVER node")
    else:
        feedback_parts.append("LUNAR_ROVER definition not found in file")

    # --- Step 4: Extract the solar_panel LightSensor block ---
    sensor_idx = wbt_content.find('name "solar_panel"')
    if sensor_idx != -1:
        # Get a context window around the sensor
        start_idx = max(0, wbt_content.rfind('LightSensor', 0, sensor_idx))
        sensor_segment = wbt_content[start_idx:sensor_idx+1000]
        
        # Verify Rotation
        rot_match = re.search(r'rotation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', sensor_segment)
        if rot_match:
            rot_vals = [float(rot_match.group(i)) for i in range(1, 5)]
            # Expected: 0 1 0 -1.5708
            if (abs(rot_vals[0] - 0.0) < 0.01 and 
                abs(rot_vals[1] - 1.0) < 0.01 and 
                abs(rot_vals[2] - 0.0) < 0.01 and 
                abs(rot_vals[3] - (-1.5708)) < 0.01):
                score += 20
                feedback_parts.append("LightSensor rotation correctly faces zenith")
            else:
                feedback_parts.append(f"LightSensor rotation incorrect: got {rot_vals}, expected [0, 1, 0, -1.5708]")
        else:
            feedback_parts.append("LightSensor rotation field not found")

        # Verify FieldOfView
        fov_match = re.search(r'fieldOfView\s+([\d.]+)', sensor_segment)
        if fov_match:
            fov = float(fov_match.group(1))
            if abs(fov - 3.1415) < 0.001:
                score += 20
                feedback_parts.append("LightSensor fieldOfView correctly set to 3.1415")
            else:
                feedback_parts.append(f"LightSensor fieldOfView incorrect: got {fov}, expected 3.1415")
        else:
            feedback_parts.append("LightSensor fieldOfView not found")

        # Verify LookupTable
        lookup_match = re.search(r'lookupTable\s*\[(.*?)\]', sensor_segment, re.DOTALL)
        if lookup_match:
            l_nums = re.findall(r'[\d.]+', lookup_match.group(1))
            if len(l_nums) >= 6:
                l_vals = [float(n) for n in l_nums]
                # Expected: [0, 0, 0, 1361, 50, 0]
                if (abs(l_vals[0] - 0) < 0.1 and abs(l_vals[1] - 0) < 0.1 and abs(l_vals[2] - 0) < 0.1 and
                    abs(l_vals[3] - 1361) < 1 and abs(l_vals[4] - 50) < 1 and abs(l_vals[5] - 0) < 0.1):
                    score += 20
                    feedback_parts.append("LightSensor lookupTable calibrated to lunar solar constant")
                else:
                    feedback_parts.append(f"LightSensor lookupTable incorrect: got {l_vals}, expected [0, 0, 0, 1361, 50, 0]")
            else:
                feedback_parts.append("LightSensor lookupTable format incorrect or missing elements")
        else:
            feedback_parts.append("LightSensor lookupTable not found")

    else:
        feedback_parts.append("LightSensor named 'solar_panel' not found in file")

    passed = score >= 75 and file_created
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }