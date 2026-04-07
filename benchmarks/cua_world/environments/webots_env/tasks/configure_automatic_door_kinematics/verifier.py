#!/usr/bin/env python3
"""
Verifier for configure_automatic_door_kinematics task.

An AMR simulation engineer must correctly configure an automatic door's sensor,
joint clearance, and motor kinematics.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Distance sensor maxRange = 4.0: 20 points
  - Joint maxStop = 1.5: 20 points
  - Motor maxVelocity = 0.8: 25 points
  - Motor maxForce = 150.0: 25 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_automatic_door_kinematics(traj, env_info, task_info):
    """
    Verify the sliding door parameters in the saved Webots world file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/hospital_door_fixed.wbt')
    expected_maxRange = metadata.get('expected_maxRange', 4.0)
    expected_maxStop = metadata.get('expected_maxStop', 1.5)
    expected_maxVelocity = metadata.get('expected_maxVelocity', 0.8)
    expected_maxForce = metadata.get('expected_maxForce', 150.0)

    score = 0
    feedback_parts = []
    
    # 1. Check export result JSON
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_door_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
        
        file_created_during_task = export_result.get("file_created_during_task", False)
    except Exception:
        file_created_during_task = False

    # 2. Copy the .wbt file
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

    # 3. Check file existence
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path} or is empty. Use File > Save World As."
        }

    score += 10
    feedback_parts.append("File exists")
    
    if not file_created_during_task:
        feedback_parts.append("(Warning: File may not have been modified during task)")

    # 4. Check maxRange
    sensor_idx = wbt_content.find('DEF DOOR_SENSOR DistanceSensor')
    if sensor_idx != -1:
        segment = wbt_content[sensor_idx:sensor_idx+300]
        m = re.search(r'maxRange\s+([\d.]+)', segment)
        if m and abs(float(m.group(1)) - expected_maxRange) < 0.1:
            score += 20
            feedback_parts.append("maxRange correct")
        else:
            val = m.group(1) if m else "not found"
            feedback_parts.append(f"maxRange incorrect (found {val}, expected {expected_maxRange})")
    else:
        feedback_parts.append("DOOR_SENSOR not found")

    # 5. Check maxStop
    params_idx = wbt_content.find('DEF DOOR_PARAMS JointParameters')
    if params_idx != -1:
        segment = wbt_content[params_idx:params_idx+300]
        m = re.search(r'maxStop\s+([\d.]+)', segment)
        if m and abs(float(m.group(1)) - expected_maxStop) < 0.1:
            score += 20
            feedback_parts.append("maxStop correct")
        else:
            val = m.group(1) if m else "not found"
            feedback_parts.append(f"maxStop incorrect (found {val}, expected {expected_maxStop})")
    else:
        feedback_parts.append("DOOR_PARAMS not found")

    # 6. Check maxVelocity and maxForce
    motor_idx = wbt_content.find('DEF DOOR_MOTOR LinearMotor')
    if motor_idx != -1:
        segment = wbt_content[motor_idx:motor_idx+300]
        
        m_vel = re.search(r'maxVelocity\s+([\d.]+)', segment)
        if m_vel and abs(float(m_vel.group(1)) - expected_maxVelocity) < 0.05:
            score += 25
            feedback_parts.append("maxVelocity correct")
        else:
            val = m_vel.group(1) if m_vel else "not found"
            feedback_parts.append(f"maxVelocity incorrect (found {val}, expected {expected_maxVelocity})")
            
        m_force = re.search(r'maxForce\s+([\d.]+)', segment)
        if m_force and abs(float(m_force.group(1)) - expected_maxForce) < 5.0:
            score += 25
            feedback_parts.append("maxForce correct")
        else:
            val = m_force.group(1) if m_force else "not found"
            feedback_parts.append(f"maxForce incorrect (found {val}, expected {expected_maxForce})")
    else:
        feedback_parts.append("DOOR_MOTOR not found")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }