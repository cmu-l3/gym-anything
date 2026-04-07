#!/usr/bin/env python3
"""
Verifier for configure_epuck_line_course task.

A robotics course instructor must configure a line-following track environment:
1. Apply the track.png texture to the arena floor.
2. Install E-puckGroundSensors into the robot.
3. Assign the e-puck_line controller.
4. Reposition the robot to the start of the track (0.36, 0.36, 0).

Scoring (100 points total):
  - File exists and modified after task start: 10 points
  - Floor has track texture (contains 'track.png'): 20 points
  - Ground sensors installed (E-puckGroundSensors): 25 points
  - Controller assigned (not <none>): 20 points
  - Robot at start position (X, Y in [0.15, 0.50]): 25 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_epuck_line_course(traj, env_info, task_info):
    """
    Verify that the e-puck line following course world has been saved with correct configs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/epuck_line_follow.wbt')
    expected_texture = metadata.get('expected_texture_name', 'track.png')
    
    # Position thresholds
    x_min = metadata.get('expected_translation_x_min', 0.15)
    x_max = metadata.get('expected_translation_x_max', 0.50)
    y_min = metadata.get('expected_translation_y_min', 0.15)
    y_max = metadata.get('expected_translation_y_max', 0.50)

    score = 0
    feedback_parts = []

    # --- Step 1: Check Export Result JSON (for Anti-Gaming) ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_epuck_line_course_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {}

    file_exists = export_result.get('file_exists', False)
    file_created_during_task = export_result.get('file_created_during_task', False)

    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world using File > Save World As."
        }

    if not file_created_during_task:
        # Anti-gaming: ensure they actually performed the save operation during the session
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file exists but was not modified during the task session. Did you save it?"
        }

    score += 10
    feedback_parts.append("World file successfully saved")

    # --- Step 2: Copy and parse the .wbt file ---
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
            "score": 10,
            "feedback": "Output file is empty or invalid."
        }

    # --- Step 3: Check Floor Texture ---
    # Looking for url containing track.png
    has_texture = bool(re.search(r'url\s*\[?\s*\"[^\"]*track\.png\"', wbt_content))
    if has_texture:
        score += 20
        feedback_parts.append("Track texture applied successfully")
    else:
        feedback_parts.append("Track texture not found in world file. Ensure ImageTexture url is set to track.png")

    # --- Step 4: Check Ground Sensors ---
    has_sensors = 'E-puckGroundSensors' in wbt_content or 'DistanceSensor' in wbt_content
    if has_sensors:
        score += 25
        feedback_parts.append("Ground sensors installed")
    else:
        feedback_parts.append("Ground sensors missing. Add E-puckGroundSensors to groundSensorsSlot")

    # --- Step 5: Check Controller ---
    controller_match = re.search(r'controller\s+\"([^\"]+)\"', wbt_content)
    if controller_match:
        actual_controller = controller_match.group(1)
        if actual_controller not in ['<none>', 'void']:
            score += 20
            feedback_parts.append(f"Controller assigned: {actual_controller}")
        else:
            feedback_parts.append(f"Controller is still '{actual_controller}' (missing behavior)")
    else:
        feedback_parts.append("Controller field not found in robot node")

    # --- Step 6: Check Position (Translation) ---
    epuck_idx = wbt_content.find('E-puck {')
    if epuck_idx == -1:
        epuck_idx = wbt_content.find('EPUCK')

    if epuck_idx != -1:
        # Search for translation directly after E-puck definition
        segment = wbt_content[epuck_idx:epuck_idx+500]
        trans_match = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', segment)
        
        if trans_match:
            tx = float(trans_match.group(1))
            ty = float(trans_match.group(2))
            
            if (x_min <= tx <= x_max) and (y_min <= ty <= y_max):
                score += 25
                feedback_parts.append(f"Robot correctly positioned at start ({tx:.2f}, {ty:.2f})")
            else:
                feedback_parts.append(f"Robot position ({tx:.2f}, {ty:.2f}) is outside expected start area ([0.15, 0.50])")
        else:
            feedback_parts.append("Could not find translation field for the E-puck")
    else:
        feedback_parts.append("E-puck robot not found in world file")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }