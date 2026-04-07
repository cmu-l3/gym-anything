#!/usr/bin/env python3
"""
Verifier for configure_patrol_sensors task.

A simulation engineer must configure Radar and RangeFinder parameters
and reposition a patrol robot to match hardware deployment specifications.

Scoring Criteria (100 points total, Pass threshold: 70):
  - 5 pts: File saved at correct path during task session
  - 15 pts: Radar maxRange ≈ 50.0
  - 15 pts: Radar horizontalFieldOfView ≈ 2.094
  - 10 pts: Radar maxSpeed ≈ 30.0
  - 15 pts: RangeFinder width = 256
  - 10 pts: RangeFinder height = 128
  - 15 pts: RangeFinder maxRange ≈ 10.0
  - 15 pts: PATROL_ROBOT translation X ≈ 5.0 and Z ≈ 5.0
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def extract_node_block(content: str, node_type: str, node_name: str) -> str:
    """
    Extracts the full text block of a Webots node matching a specific type and name.
    Properly handles balanced braces to isolate just the node's properties.
    """
    pattern = re.compile(rf'{node_type}\s*\{{')
    for match in pattern.finditer(content):
        start_idx = match.end()
        depth = 1
        for i in range(start_idx, len(content)):
            if content[i] == '{':
                depth += 1
            elif content[i] == '}':
                depth -= 1
            
            if depth == 0:
                block = content[match.start():i+1]
                # Check if this block contains the required name
                if re.search(rf'name\s+"{node_name}"', block):
                    return block
                break
    return ""


def verify_configure_patrol_sensors(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/patrol_robot_configured.wbt')
    
    score = 0
    feedback_parts = []
    
    # 1. Check Export Result JSON
    try:
        res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        res_file.close()
        copy_from_env('/tmp/task_result.json', res_file.name)
        with open(res_file.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(res_file.name)
    except Exception as e:
        logger.warning(f"Failed to read task_result.json: {e}")
        export_result = {}

    file_exists = export_result.get('file_exists', False)
    file_modified = export_result.get('file_modified_during_task', False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"World file not found at {output_path}. You must save using File > Save World As."
        }
        
    if file_modified:
        score += 5
        feedback_parts.append("File correctly saved during task")
    else:
        feedback_parts.append("File exists but was not modified during the task (possible gaming attempt)")

    # 2. Extract and Parse the .wbt File
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error reading world file: {e}"}

    # --- Verify Radar Configuration ---
    radar_block = extract_node_block(wbt_content, 'Radar', metadata.get('radar_name', 'patrol_radar'))
    if radar_block:
        # Check maxRange
        mr_match = re.search(r'maxRange\s+([\d.]+)', radar_block)
        if mr_match:
            val = float(mr_match.group(1))
            if 45.0 <= val <= 55.0:
                score += 15
                feedback_parts.append(f"Radar maxRange set to {val}")
            else:
                feedback_parts.append(f"Radar maxRange incorrect: {val} (expected 50.0)")
        else:
            feedback_parts.append("Radar maxRange field missing")
            
        # Check horizontalFieldOfView
        hfov_match = re.search(r'horizontalFieldOfView\s+([\d.]+)', radar_block)
        if hfov_match:
            val = float(hfov_match.group(1))
            if 1.9 <= val <= 2.2:
                score += 15
                feedback_parts.append(f"Radar horizontalFieldOfView set to {val}")
            else:
                feedback_parts.append(f"Radar horizontalFieldOfView incorrect: {val} (expected 2.094)")
        else:
            feedback_parts.append("Radar horizontalFieldOfView field missing")
            
        # Check maxSpeed
        ms_match = re.search(r'maxSpeed\s+([\d.]+)', radar_block)
        if ms_match:
            val = float(ms_match.group(1))
            if 25.0 <= val <= 35.0:
                score += 10
                feedback_parts.append(f"Radar maxSpeed set to {val}")
            else:
                feedback_parts.append(f"Radar maxSpeed incorrect: {val} (expected 30.0)")
        else:
            feedback_parts.append("Radar maxSpeed field missing")
    else:
        feedback_parts.append("Radar node 'patrol_radar' not found or malformed")

    # --- Verify RangeFinder Configuration ---
    rf_block = extract_node_block(wbt_content, 'RangeFinder', metadata.get('rangefinder_name', 'obstacle_rangefinder'))
    if rf_block:
        # Check width
        w_match = re.search(r'width\s+(\d+)', rf_block)
        if w_match:
            val = int(w_match.group(1))
            if val == 256:
                score += 15
                feedback_parts.append("RangeFinder width correctly set to 256")
            else:
                feedback_parts.append(f"RangeFinder width incorrect: {val} (expected 256)")
        else:
            feedback_parts.append("RangeFinder width field missing")
            
        # Check height
        h_match = re.search(r'height\s+(\d+)', rf_block)
        if h_match:
            val = int(h_match.group(1))
            if val == 128:
                score += 10
                feedback_parts.append("RangeFinder height correctly set to 128")
            else:
                feedback_parts.append(f"RangeFinder height incorrect: {val} (expected 128)")
        else:
            feedback_parts.append("RangeFinder height field missing")
            
        # Check maxRange
        rf_mr_match = re.search(r'maxRange\s+([\d.]+)', rf_block)
        if rf_mr_match:
            val = float(rf_mr_match.group(1))
            if 8.0 <= val <= 12.0:
                score += 15
                feedback_parts.append(f"RangeFinder maxRange set to {val}")
            else:
                feedback_parts.append(f"RangeFinder maxRange incorrect: {val} (expected 10.0)")
        else:
            feedback_parts.append("RangeFinder maxRange field missing")
    else:
        feedback_parts.append("RangeFinder node 'obstacle_rangefinder' not found or malformed")

    # --- Verify Robot Translation ---
    # Extract translation specifically from PATROL_ROBOT
    def_idx = wbt_content.find('DEF PATROL_ROBOT Robot')
    if def_idx != -1:
        robot_header_block = wbt_content[def_idx:def_idx+300]
        trans_match = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', robot_header_block)
        if trans_match:
            x = float(trans_match.group(1))
            z = float(trans_match.group(3))
            if 4.0 <= x <= 6.0 and 4.0 <= z <= 6.0:
                score += 15
                feedback_parts.append(f"Robot successfully moved to X:{x}, Z:{z}")
            else:
                feedback_parts.append(f"Robot translation incorrect: X:{x}, Z:{z} (expected X:5.0, Z:5.0)")
        else:
            feedback_parts.append("Robot translation field not found")
    else:
        feedback_parts.append("DEF PATROL_ROBOT node not found")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }