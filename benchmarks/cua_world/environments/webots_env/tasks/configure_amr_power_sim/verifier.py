#!/usr/bin/env python3
"""
Verifier for configure_amr_power_sim task.

An AMR systems engineer must configure the energy consumption and battery capacity
parameters for a delivery robot in Webots.

Scoring (100 points total):
  - File correctly saved during task time: 10 points
  - Battery list correctly populated [1800000, 1800000, 2000]: 30 points
  - cpuConsumption set to 15.0: 20 points
  - left_wheel_motor consumptionFactor set to 3.5: 20 points
  - right_wheel_motor consumptionFactor set to 3.5: 20 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

def verify_configure_amr_power_sim(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the AMR power simulation was configured correctly based on the JSON output.
    Uses multi-criteria verification and anti-gaming timestamp checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy the JSON result
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    
    try:
        copy_from_env('/tmp/amr_power_sim_result.json', result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File existence and anti-gaming check (10 pts)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file /home/ga/Desktop/amr_power_sim.wbt not found. The world was not saved."
        }
    
    file_mtime = result.get("file_mtime", 0)
    task_start = result.get("task_start_timestamp", 0)
    
    if file_mtime >= task_start and task_start > 0:
        score += 10
        feedback_parts.append("File correctly saved during task")
    else:
        # Give partial credit but flag timestamp issue
        score += 5
        feedback_parts.append("File exists, but modification time check failed")

    # 2. Battery configuration (30 pts)
    # Expected: [1800000, 1800000, 2000]
    expected_battery = [1800000.0, 1800000.0, 2000.0]
    actual_battery = result.get("battery", [])
    
    if len(actual_battery) == 3:
        if actual_battery == expected_battery:
            score += 30
            feedback_parts.append("Battery capacity and charge rate correctly configured")
        else:
            # Partial credit for adding exactly 3 values but getting values slightly wrong
            score += 10
            feedback_parts.append(f"Battery values incorrect. Expected {expected_battery}, got {actual_battery}")
    elif len(actual_battery) > 0:
        feedback_parts.append(f"Battery array has incorrect number of elements ({len(actual_battery)} instead of 3)")
    else:
        feedback_parts.append("Battery field was left empty or not found")

    # 3. CPU Consumption (20 pts)
    expected_cpu = 15.0
    actual_cpu = result.get("cpuConsumption", 0.0)
    
    if abs(actual_cpu - expected_cpu) < 0.1:
        score += 20
        feedback_parts.append("cpuConsumption correctly set to 15.0W")
    else:
        feedback_parts.append(f"cpuConsumption is {actual_cpu}W (expected {expected_cpu}W)")

    # 4. Left Motor Consumption Factor (20 pts)
    expected_motor = 3.5
    left_motor = result.get("left_motor_consumption", 0.0)
    
    if abs(left_motor - expected_motor) < 0.1:
        score += 20
        feedback_parts.append("left_wheel_motor consumptionFactor correctly set to 3.5")
    else:
        feedback_parts.append(f"left_wheel_motor consumptionFactor is {left_motor} (expected {expected_motor})")

    # 5. Right Motor Consumption Factor (20 pts)
    right_motor = result.get("right_motor_consumption", 0.0)
    
    if abs(right_motor - expected_motor) < 0.1:
        score += 20
        feedback_parts.append("right_wheel_motor consumptionFactor correctly set to 3.5")
    else:
        feedback_parts.append(f"right_wheel_motor consumptionFactor is {right_motor} (expected {expected_motor})")

    # 6. VLM Check for Trajectory (Ensures Agent interacted with Webots rather than faking file)
    vlm_feedback = ""
    frames = sample_trajectory_frames(traj, n=5)
    if frames and len(frames) > 0:
        vlm_prompt = (
            "Look at these screenshots showing an agent's workflow. "
            "Is the agent interacting with the Webots 3D simulator (e.g., editing the Scene Tree, "
            "using text editors, or viewing the 3D robot)? "
            "Respond ONLY with valid JSON: {\"is_using_webots\": true/false}"
        )
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if not parsed.get("is_using_webots", False):
                    # Penalty for spoofing
                    score -= 50
                    vlm_feedback = " [VLM Penalty: Workflow doesn't appear to show Webots interactions]"
        except Exception as e:
            logger.warning(f"VLM verification failed, skipping penalty: {e}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts) + vlm_feedback
    }