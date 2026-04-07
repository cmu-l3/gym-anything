#!/usr/bin/env python3
"""
Verifier for configure_satellite_reaction_wheels task.

This verifier checks if the user has correctly modified the `.wbt` file to match
the zero-G vacuum environment and the exact specifications of the CubeSat reaction wheels.
"""

import json
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_satellite_reaction_wheels(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('expected_output_path', '/home/ga/Desktop/cubesat_adcs_configured.wbt')
    
    score = 0
    feedback_parts = []
    
    # 1. Check Export Metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file not found at {output_path}. Did you save the world?"
        }
        
    if not result.get('file_created_during_task', False):
        feedback_parts.append("Warning: Output file timestamp predates task start (possible anti-gaming flag).")
    else:
        score += 10
        feedback_parts.append("File correctly saved during task.")

    # 2. Copy the actual WBT file to inspect
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read the saved .wbt file: {e}"}
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # 3. Check Gravity (0 0 0)
    # Match lines like: gravity 0 0 0 or gravity 0.0 0.0 0.0
    grav_match = re.search(r'gravity\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
    if grav_match:
        gx, gy, gz = map(float, grav_match.groups())
        if abs(gx) < 0.001 and abs(gy) < 0.001 and abs(gz) < 0.001:
            score += 10
            feedback_parts.append("Zero gravity verified.")
        else:
            feedback_parts.append(f"Gravity is ({gx}, {gy}, {gz}), expected (0, 0, 0).")
    else:
        feedback_parts.append("Gravity field not found in WorldInfo.")

    # 4. Check Damping (linear 0, angular 0)
    # We look for a Damping block that has linear 0 and angular 0
    damping_blocks = re.findall(r'Damping\s*\{([^\}]+)\}', wbt_content)
    zero_damping_found = False
    for block in damping_blocks:
        lin_match = re.search(r'linear\s+([\d.]+)', block)
        ang_match = re.search(r'angular\s+([\d.]+)', block)
        lin = float(lin_match.group(1)) if lin_match else 0.2  # Webots default is 0.2
        ang = float(ang_match.group(1)) if ang_match else 0.2
        if abs(lin) < 0.001 and abs(ang) < 0.001:
            zero_damping_found = True
            break
            
    if zero_damping_found:
        score += 20
        feedback_parts.append("Zero damping verified.")
    else:
        feedback_parts.append("No Damping block found with linear=0 and angular=0.")

    # 5. Check Motors and Masses
    # Find all RotationalMotor devices and their maxVelocity / maxTorque
    velocities = [float(v) for v in re.findall(r'maxVelocity\s+([\d.]+)', wbt_content)]
    torques = [float(t) for t in re.findall(r'maxTorque\s+([\d.]+)', wbt_content)]
    
    # Exclude the main robot mass (1.33) and count how many masses are 0.12
    masses = [float(m) for m in re.findall(r'mass\s+([\d.]+)', wbt_content)]

    count_vel = sum(1 for v in velocities if abs(v - 600.0) < 0.1)
    count_torque = sum(1 for t in torques if abs(t - 0.05) < 0.001)
    count_mass = sum(1 for m in masses if abs(m - 0.12) < 0.001)

    vel_score = min(20, int((count_vel / 3.0) * 20))
    score += vel_score
    if count_vel == 3:
        feedback_parts.append("All 3 wheel velocities configured.")
    else:
        feedback_parts.append(f"Only {count_vel}/3 wheels have correct velocity (600.0).")

    torque_score = min(20, int((count_torque / 3.0) * 20))
    score += torque_score
    if count_torque == 3:
        feedback_parts.append("All 3 wheel torques configured.")
    else:
        feedback_parts.append(f"Only {count_torque}/3 wheels have correct torque (0.05).")

    mass_score = min(20, int((count_mass / 3.0) * 20))
    score += mass_score
    if count_mass == 3:
        feedback_parts.append("All 3 wheel masses configured.")
    else:
        feedback_parts.append(f"Only {count_mass}/3 wheels have correct mass (0.12).")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }