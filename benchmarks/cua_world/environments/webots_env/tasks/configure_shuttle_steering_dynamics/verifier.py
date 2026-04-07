#!/usr/bin/env python3
"""
Verifier for configure_shuttle_steering_dynamics task.

A vehicle dynamics engineer must configure physical joint limits and motor speeds
for an autonomous shuttle in Webots to match physical hardware.

Scoring (100 points total):
  - File exists and was created during task: 10 points
  - Steering joint limits (minStop -0.65, maxStop 0.65): 20 points
  - Steering motor velocity (maxVelocity 1.5): 20 points
  - Drive motor velocity (maxVelocity 15): 15 points
  - Drive motor torque (maxTorque 350): 15 points
  - VLM confirmation of UI interaction: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance in Webots. 
The agent's task was to configure 'HingeJointParameters' (minStop, maxStop) and 'RotationalMotor' properties (maxVelocity, maxTorque) in the Webots scene tree.

Examine these trajectory frames. Do you see evidence that the agent successfully navigated the Webots scene tree on the left side of the screen, expanded the robot nodes, and edited the values in the properties panel at the bottom left?

Return ONLY a JSON object with this exact format:
{
    "interacted_with_scene_tree": true/false,
    "edited_properties": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_configure_shuttle_steering_dynamics(traj, env_info, task_info):
    """
    Verify the shuttle's parameters were correctly applied and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/shuttle_dynamics.wbt')
    
    score = 0
    feedback_parts = []
    
    # 1. Read JSON result from export_result.sh
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    try:
        copy_from_env('/tmp/task_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        export_result = {}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    # Check file existence and anti-gaming timestamp
    output_exists = export_result.get('output_exists', False)
    file_created_during_task = export_result.get('file_created_during_task', False)

    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world."
        }
        
    if not file_created_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file existed before task started. Anti-gaming check failed."
        }
        
    score += 10
    feedback_parts.append("File saved successfully")

    # 2. Copy the .wbt file to parse the VRML fields
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    if len(wbt_content) < 100:
        return {
            "passed": False,
            "score": score,
            "feedback": "Saved world file is empty or corrupted."
        }

    # 3. VRML Parameter Counting
    
    # Count physical steering limits: "minStop -0.65" and "maxStop 0.65"
    min_stop_count = len(re.findall(r'minStop\s+-0\.65', wbt_content))
    max_stop_count = len(re.findall(r'maxStop\s+0\.65', wbt_content))
    
    if min_stop_count >= 2 and max_stop_count >= 2:
        score += 20
        feedback_parts.append(f"Steering limits correctly applied (minStop=-0.65, maxStop=0.65)")
    elif min_stop_count >= 1 or max_stop_count >= 1:
        score += 10
        feedback_parts.append(f"Steering limits partially applied ({min_stop_count}/2 minStops, {max_stop_count}/2 maxStops)")
    else:
        feedback_parts.append("Steering physical limits not found")

    # Count steering motor speed: "maxVelocity 1.5"
    steer_vel_count = len(re.findall(r'maxVelocity\s+1\.5', wbt_content))
    
    if steer_vel_count >= 2:
        score += 20
        feedback_parts.append(f"Steering velocity correctly applied (maxVelocity 1.5)")
    elif steer_vel_count == 1:
        score += 10
        feedback_parts.append(f"Steering velocity partially applied ({steer_vel_count}/2 motors)")
    else:
        feedback_parts.append("Steering velocity not found")

    # Count drive motor speed: "maxVelocity 15"
    drive_vel_count = len(re.findall(r'maxVelocity\s+15(?:\.0)?', wbt_content))
    
    if drive_vel_count >= 2:
        score += 15
        feedback_parts.append(f"Drive velocity correctly applied (maxVelocity 15.0)")
    elif drive_vel_count == 1:
        score += 7
        feedback_parts.append(f"Drive velocity partially applied ({drive_vel_count}/2 motors)")
    else:
        feedback_parts.append("Drive velocity not found")

    # Count drive motor torque: "maxTorque 350"
    drive_torque_count = len(re.findall(r'maxTorque\s+350(?:\.0)?', wbt_content))
    
    if drive_torque_count >= 2:
        score += 15
        feedback_parts.append(f"Drive torque correctly applied (maxTorque 350.0)")
    elif drive_torque_count == 1:
        score += 7
        feedback_parts.append(f"Drive torque partially applied ({drive_torque_count}/2 motors)")
    else:
        feedback_parts.append("Drive torque not found")

    # 4. VLM Trajectory Verification
    vlm_points = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=images)
            try:
                if vlm_response.get("success"):
                    parsed = vlm_response.get("parsed", {})
                    interacted = parsed.get("interacted_with_scene_tree", False)
                    edited = parsed.get("edited_properties", False)
                    
                    if interacted and edited:
                        vlm_points = 20
                        feedback_parts.append("VLM confirmed scene tree interaction")
                    elif interacted or edited:
                        vlm_points = 10
                        feedback_parts.append("VLM partially confirmed UI interaction")
                    else:
                        feedback_parts.append("VLM did not detect scene tree property editing")
                else:
                    feedback_parts.append(f"VLM query failed: {vlm_response.get('error')}")
                    # Give benefit of doubt if VLM fails but parameters are perfect
                    if score >= 80:
                        vlm_points = 20
            except Exception as e:
                logger.error(f"Error parsing VLM response: {e}")
                if score >= 80:
                    vlm_points = 20
        else:
            feedback_parts.append("No trajectory images available for VLM verification")
    else:
        # If VLM is not available in environment, grant points if file parsing passed
        if score >= 80:
            vlm_points = 20
            
    score += vlm_points

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }