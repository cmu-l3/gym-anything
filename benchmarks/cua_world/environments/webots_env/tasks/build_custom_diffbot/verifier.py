#!/usr/bin/env python3
"""
Verifier for build_custom_diffbot task.

Scoring (100 points total):
  - File exists at correct path (≥500 bytes): 10 pts
  - Robot node present: 10 pts
  - At least 2 HingeJoint children: 15 pts
  - Motor left_motor found: 10 pts
  - Motor right_motor found: 10 pts
  - Robot Physics with mass > 0.1: 15 pts
  - DistanceSensor front_sensor present: 15 pts
  - Cylinder geometry present (wheels): 5 pts
  - Floor/Arena node exists: 5 pts
  - basicTimeStep <= 64: 5 pts

Pass threshold: 60 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_build_custom_diffbot(traj, env_info, task_info):
    """
    Verify that the agent built a complete differential-drive robot from scratch.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('expected_output_path', '/home/ga/Desktop/my_robot.wbt')

    score = 0
    feedback_parts = []
    
    # --- Read export result JSON ---
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    try:
        copy_from_env('/tmp/build_custom_diffbot_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not read export result: {e}")
        export_result = {}
        try:
            os.unlink(result_file.name)
        except Exception:
            pass

    file_exists = export_result.get('file_exists', False)
    file_size = export_result.get('file_size_bytes', 0)
    file_mtime = export_result.get('file_mtime', 0)
    task_start = export_result.get('task_start_timestamp', 0)
    
    # --- Check anti-gaming (file creation time) ---
    if file_exists and file_mtime >= task_start:
        pass # Created during task
    elif file_exists:
        feedback_parts.append("Warning: File timestamp is older than task start time.")

    # --- Copy the .wbt file for text analysis ---
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

    if not wbt_content or file_size < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or empty at {output_path}. You must save the world.",
            "details": {"file_exists": False}
        }
        
    # 1. File size (10 pts)
    if file_size >= 500:
        score += 10
        feedback_parts.append("File exists and has sufficient size")
    else:
        score += 5
        feedback_parts.append(f"File exists but is very small ({file_size} bytes)")

    # 2. Robot node present (10 pts)
    if re.search(r'\bRobot\s*\{', wbt_content):
        score += 10
        feedback_parts.append("Robot node found")
    else:
        feedback_parts.append("Robot node missing")

    # 3. At least 2 HingeJoint children (15 pts)
    hinge_joints = len(re.findall(r'\bHingeJoint\s*\{', wbt_content))
    if hinge_joints >= 2:
        score += 15
        feedback_parts.append(f"Found {hinge_joints} HingeJoints")
    elif hinge_joints == 1:
        score += 7
        feedback_parts.append("Found 1 HingeJoint (expected 2)")
    else:
        feedback_parts.append("HingeJoint missing")

    # 4. left_motor (10 pts)
    if 'left_motor' in wbt_content:
        score += 10
        feedback_parts.append("left_motor found")
    else:
        feedback_parts.append("left_motor missing")

    # 5. right_motor (10 pts)
    if 'right_motor' in wbt_content:
        score += 10
        feedback_parts.append("right_motor found")
    else:
        feedback_parts.append("right_motor missing")

    # 6. Physics with mass > 0.1 (15 pts)
    masses = re.findall(r'\bmass\s+([\d.]+)', wbt_content)
    if masses:
        valid_mass = False
        for m in masses:
            try:
                if float(m) > 0.1:
                    valid_mass = True
                    break
            except ValueError:
                pass
        if valid_mass:
            score += 15
            feedback_parts.append("Physics node with mass > 0.1 found")
        else:
            feedback_parts.append(f"Masses found but none > 0.1: {masses}")
    else:
        feedback_parts.append("No mass value found (Physics node missing or default mass)")

    # 7. front_sensor (15 pts)
    if re.search(r'\bDistanceSensor\s*\{', wbt_content) and 'front_sensor' in wbt_content:
        score += 15
        feedback_parts.append("DistanceSensor 'front_sensor' found")
    elif 'front_sensor' in wbt_content:
        score += 5
        feedback_parts.append("'front_sensor' name found but not inside DistanceSensor")
    else:
        feedback_parts.append("DistanceSensor 'front_sensor' missing")

    # 8. Cylinder geometry (5 pts)
    if re.search(r'\bCylinder\s*\{', wbt_content):
        score += 5
        feedback_parts.append("Cylinder geometry found")
    else:
        feedback_parts.append("Cylinder geometry missing")

    # 9. Floor/Arena (5 pts)
    if re.search(r'\bRectangleArena\s*\{', wbt_content) or re.search(r'\bFloor\s*\{', wbt_content) or 'RectangleArena' in wbt_content:
        score += 5
        feedback_parts.append("Floor/Arena found")
    else:
        feedback_parts.append("Floor/Arena missing")

    # 10. basicTimeStep <= 64 (5 pts)
    ts_match = re.search(r'\bbasicTimeStep\s+(\d+)', wbt_content)
    if ts_match:
        ts = int(ts_match.group(1))
        if ts <= 64:
            score += 5
            feedback_parts.append(f"basicTimeStep ({ts}) is acceptable")
        else:
            feedback_parts.append(f"basicTimeStep ({ts}) is too high")
    else:
        feedback_parts.append("basicTimeStep not found")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }