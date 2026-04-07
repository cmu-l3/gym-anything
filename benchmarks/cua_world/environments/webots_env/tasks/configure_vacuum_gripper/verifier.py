#!/usr/bin/env python3
"""
Verifier for configure_vacuum_gripper task.

Checks whether the agent successfully added a VacuumGripper node to the 
WRIST_LINK and configured its parameters correctly.

Scoring (100 points total):
  - Output file exists & created during task: 10 points
  - VacuumGripper node present: 20 points
  - Translation set to 0 0 0.05: 10 points
  - isOn set to TRUE: 10 points
  - name set to "piab_array": 10 points
  - tensileStrength set to 480: 15 points
  - shearStrength set to 240: 15 points
  - contactMaterial set to "piab_rubber": 10 points

Pass Threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging
import sys

# Add gym_anything paths for VLM utilities
sys.path.insert(0, '/workspace')
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent interacting with the Webots 3D simulator.
The agent's task is to add a 'VacuumGripper' node to the robot's WRIST_LINK and configure its parameters.

Please review the provided trajectory frames and the final screenshot.
Did the agent actively use the Webots UI to navigate the Scene Tree (left panel) and modify node fields (bottom-left panel)?
Look for:
1. The Scene Tree expanded to show the robot hierarchy (e.g., WRIST_LINK, VacuumGripper).
2. The Field Editor showing properties like tensileStrength, shearStrength, or translation.
3. The "Add Node" dialog box being used at any point.

Respond with JSON exactly:
{
    "interacted_with_scene_tree": true/false,
    "edited_fields": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_configure_vacuum_gripper(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/palletizer_gripper.wbt')
    expected_z = metadata.get('expected_translation_z', 0.05)
    expected_name = metadata.get('expected_name', 'piab_array')
    expected_tensile = metadata.get('expected_tensile', 480.0)
    expected_shear = metadata.get('expected_shear', 240.0)
    expected_material = metadata.get('expected_material', 'piab_rubber')

    score = 0
    feedback_parts = []

    # --- Step 1: Read Export JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/configure_vacuum_gripper_result.json', temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read export JSON: {e}")
        export_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    file_exists = export_result.get('file_exists', False)
    file_created = export_result.get('file_created_during_task', False)

    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file not found at {output_path}. You must save the world via File > Save World As."
        }
        
    if not file_created:
        feedback_parts.append("WARNING: File appears to be older than the task start time.")
    else:
        score += 10
        feedback_parts.append("File saved successfully.")

    # --- Step 2: Copy and Parse .wbt File ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
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

    # Find the VacuumGripper block
    gripper_idx = wbt_content.find('VacuumGripper {')
    if gripper_idx == -1:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | VacuumGripper node not found in the saved world."
        }
        
    score += 20
    feedback_parts.append("VacuumGripper node present.")

    # Extract block string for the gripper (approx 500 chars to cover its properties safely)
    gripper_block = wbt_content[gripper_idx:gripper_idx+600]

    # Check Translation (0 0 0.05)
    trans_match = re.search(r'translation\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', gripper_block)
    if trans_match:
        z_val = float(trans_match.group(3))
        if abs(z_val - expected_z) < 0.001:
            score += 10
            feedback_parts.append("Translation correct.")
        else:
            feedback_parts.append(f"Translation Z is {z_val}, expected {expected_z}.")
    else:
        feedback_parts.append("Translation not found in VacuumGripper.")

    # Check name
    name_match = re.search(r'name\s+"([^"]+)"', gripper_block)
    if name_match and name_match.group(1) == expected_name:
        score += 10
        feedback_parts.append("Name correct.")
    else:
        found_name = name_match.group(1) if name_match else "none"
        feedback_parts.append(f"Name is '{found_name}', expected '{expected_name}'.")

    # Check isOn
    is_on_match = re.search(r'isOn\s+(TRUE|FALSE)', gripper_block)
    if is_on_match and is_on_match.group(1) == "TRUE":
        score += 10
        feedback_parts.append("isOn is TRUE.")
    else:
        feedback_parts.append("isOn is not TRUE.")

    # Check tensileStrength
    tensile_match = re.search(r'tensileStrength\s+([\d.-]+)', gripper_block)
    if tensile_match and abs(float(tensile_match.group(1)) - expected_tensile) < 0.1:
        score += 15
        feedback_parts.append("Tensile strength correct.")
    else:
        found_t = tensile_match.group(1) if tensile_match else "none"
        feedback_parts.append(f"Tensile strength is {found_t}, expected {expected_tensile}.")

    # Check shearStrength
    shear_match = re.search(r'shearStrength\s+([\d.-]+)', gripper_block)
    if shear_match and abs(float(shear_match.group(1)) - expected_shear) < 0.1:
        score += 15
        feedback_parts.append("Shear strength correct.")
    else:
        found_s = shear_match.group(1) if shear_match else "none"
        feedback_parts.append(f"Shear strength is {found_s}, expected {expected_shear}.")

    # Check contactMaterial
    material_match = re.search(r'contactMaterial\s+"([^"]+)"', gripper_block)
    if material_match and material_match.group(1) == expected_material:
        score += 10
        feedback_parts.append("Contact material correct.")
    else:
        found_m = material_match.group(1) if material_match else "none"
        feedback_parts.append(f"Contact material is '{found_m}', expected '{expected_material}'.")

    # --- Step 3: VLM Trajectory Verification ---
    vlm_feedback = "VLM not available."
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
            
            if frames:
                vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    interacted = parsed.get("interacted_with_scene_tree", False)
                    vlm_feedback = "VLM confirmed UI interaction." if interacted else "VLM could not confirm UI interaction."
                else:
                    vlm_feedback = "VLM request failed."
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            vlm_feedback = f"VLM error: {e}"

    feedback_parts.append(vlm_feedback)
    
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }