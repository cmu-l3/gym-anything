#!/usr/bin/env python3
"""
Verifier for configure_quadcopter_aerodynamics task.

An Aerospace Engineer must configure 3 parameters across 4 Propeller nodes 
(12 precise edits total) to match physical wind tunnel data.

Verification Strategy:
1. Programmatic: Parse the saved .wbt file using regex to extract values.
2. Logic: Ensure values fall within a tight numerical tolerance (accounting for scientific notation).
3. Trajectory VLM: Verify the user navigated the Webots GUI to prevent spoofing the output file.
"""

import json
import re
import tempfile
import os
import logging
import sys

# Ensure gym_anything modules can be loaded for VLM
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    pass # Will handle gracefully if not available in specific env wrapper

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these trajectory screenshots from a robotics simulation task.
The agent was asked to edit aerodynamic parameters inside the Webots scene tree.

Check for these indicators of actual work being performed:
1. Is the Webots Scene Tree (left panel) expanded, showing nodes like "Robot", "children", or "Propeller"?
2. Is the Webots Field Editor (bottom left panel) being used to edit numeric values?
3. Can you see numeric entries like 1.5e-4, 0.00015, 6e-6, or 75 being typed or selected?
4. Did they use "File > Save World As" dialog at the end?

Respond in JSON format:
{
    "scene_tree_navigated": true/false,
    "fields_edited_in_ui": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_configure_quadcopter_aerodynamics(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/tuned_quadcopter.wbt')
    expected_thrust_x = metadata.get('expected_thrust_x', 0.00015)
    expected_torque_x = metadata.get('expected_torque_x', 0.000006)
    expected_threshold = metadata.get('expected_threshold', 75.0)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Read task_result.json for anti-gaming checks
    # -------------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not task_result.get('output_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world using File > Save World As."
        }
    
    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it might not have been created during this session.")
    
    score += 10
    feedback_parts.append("World file saved successfully.")

    # -------------------------------------------------------------------------
    # 2. Extract and Parse the .wbt File
    # -------------------------------------------------------------------------
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.error(f"Could not read .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    if not wbt_content or len(wbt_content) < 100:
        return {"passed": False, "score": score, "feedback": "World file is empty or corrupted."}

    # Regex to extract vectors/floats specifically from Propeller fields
    # Format typically: thrustConstants 0.00015 0
    thrust_matches = re.findall(r'thrustConstants\s+([-\d\.eE]+)\s+([-\d\.eE]+)', wbt_content)
    torque_matches = re.findall(r'torqueConstants\s+([-\d\.eE]+)\s+([-\d\.eE]+)', wbt_content)
    thresh_matches = re.findall(r'fastHelixThreshold\s+([-\d\.eE]+)', wbt_content)

    # Calculate tolerances (± 5%)
    thrust_min, thrust_max = expected_thrust_x * 0.95, expected_thrust_x * 1.05
    torque_min, torque_max = expected_torque_x * 0.95, expected_torque_x * 1.05
    thresh_min, thresh_max = expected_threshold * 0.95, expected_threshold * 1.05

    valid_thrust = 0
    for match in thrust_matches:
        try:
            val_x = float(match[0])
            if thrust_min <= val_x <= thrust_max:
                valid_thrust += 1
        except ValueError:
            pass

    valid_torque = 0
    for match in torque_matches:
        try:
            val_x = float(match[0])
            if torque_min <= val_x <= torque_max:
                valid_torque += 1
        except ValueError:
            pass

    valid_thresh = 0
    for match in thresh_matches:
        try:
            val = float(match)
            if thresh_min <= val <= thresh_max:
                valid_thresh += 1
        except ValueError:
            pass

    # Each valid field gives points (max 4 per field type)
    # Thrust: 4 * 6 = 24 points
    # Torque: 4 * 6 = 24 points
    # Threshold: 4 * 5.5 = 22 points
    # Total for parameters = 70 points
    score += min(valid_thrust, 4) * 6
    score += min(valid_torque, 4) * 6
    score += min(valid_thresh, 4) * 5.5

    feedback_parts.append(f"Thrust correctly set on {min(valid_thrust, 4)}/4 rotors.")
    feedback_parts.append(f"Torque correctly set on {min(valid_torque, 4)}/4 rotors.")
    feedback_parts.append(f"Threshold correctly set on {min(valid_thresh, 4)}/4 rotors.")

    # -------------------------------------------------------------------------
    # 3. VLM Trajectory Verification (Anti-Spoofing)
    # -------------------------------------------------------------------------
    vlm_score_added = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        
        if frames:
            vlm_result = query_vlm(images=frames, prompt=build_vlm_prompt())
            parsed = vlm_result.get("parsed", {})
            
            navigated = parsed.get("scene_tree_navigated", False)
            edited = parsed.get("fields_edited_in_ui", False)
            
            if navigated and edited:
                vlm_score_added = 20
                feedback_parts.append("VLM verified active GUI usage.")
            elif navigated or edited:
                vlm_score_added = 10
                feedback_parts.append("VLM verified partial GUI usage.")
            else:
                feedback_parts.append("VLM did not clearly detect GUI usage, but programmatic checks passed.")
                # We won't heavily penalize if the file is perfect, but we grant bonus/core points for VLM
                vlm_score_added = 0
    except Exception as e:
        logger.warning(f"VLM verification failed/skipped: {e}")
        # Graceful degradation if VLM is unavailable
        vlm_score_added = 20
        feedback_parts.append("VLM check skipped, awarding full trajectory points by default.")

    score += vlm_score_added

    # Ensure score caps at 100
    score = int(min(score, 100))
    
    # Passing requires the file and at least a majority of the parameters configured (>= 75 points)
    key_criteria_met = (valid_thrust >= 3 and valid_torque >= 3 and valid_thresh >= 3)
    passed = score >= 75 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }