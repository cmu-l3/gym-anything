#!/usr/bin/env python3
"""
Verifier for configure_prosthetic_tactile_sensors task.

A biomedical robotics engineer must upgrade a kinematic simulation to a sensorimotor
testbed by converting rigid bodies to TouchSensors, adding correct force measurement
parameters, and tuning grasping physics.

Scoring (100 points total):
  - File saved correctly (must be created during task): 10 points
  - WorldInfo basicTimeStep <= 16: 15 points
  - TEST_EGG has Physics with mass ~0.05: 25 points
  - INDEX_TIP & THUMB_TIP converted to TouchSensor: 20 points
  - Sensors have type "force-3d": 15 points
  - Sensors have resolution 0.001: 15 points

Anti-gaming:
  - Both "Nodes Converted" and "Egg Physics Enabled" must be strictly met to pass.
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def extract_node_block(content: str, def_name: str) -> str:
    """Extracts the entire block starting with DEF <def_name> until its closing brace."""
    idx = content.find(f"DEF {def_name}")
    if idx == -1:
        return ""
    brace_start = content.find("{", idx)
    if brace_start == -1:
        return ""
    
    depth = 1
    for i in range(brace_start + 1, len(content)):
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
        if depth == 0:
            return content[idx:i+1]
    return content[idx:]  # Fallback if unclosed


def verify_configure_prosthetic_tactile_sensors(traj, env_info, task_info):
    """
    Verify the prosthetic grasp world has been correctly modified and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/prosthetic_grasp_test.wbt')
    expected_timestep = metadata.get('expected_timestep', 16)
    expected_mass = metadata.get('expected_egg_mass', 0.05)
    
    egg_def = metadata.get('egg_def', 'TEST_EGG')
    index_def = metadata.get('index_def', 'INDEX_TIP')
    thumb_def = metadata.get('thumb_def', 'THUMB_TIP')

    score = 0
    feedback_parts = []

    # --- Step 1: Parse the export result JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result_data.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world via File > Save World As."
        }

    if not result_data.get('file_created_during_task', True):
        feedback_parts.append("WARNING: File was not created/modified during the task window.")

    score += 10
    feedback_parts.append("World file saved at correct path.")

    # --- Step 2: Extract and parse the .wbt file ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_content = ""
    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read saved .wbt file: {e}"}
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # --- Check Timestep ---
    timestep_match = re.search(r'basicTimeStep\s+([\d.]+)', wbt_content)
    if timestep_match:
        actual_timestep = float(timestep_match.group(1))
        if actual_timestep <= expected_timestep:
            score += 15
            feedback_parts.append(f"basicTimeStep appropriately tuned to {actual_timestep}.")
        else:
            feedback_parts.append(f"basicTimeStep is {actual_timestep}, should be <= {expected_timestep} for grasping physics.")
    else:
        feedback_parts.append("basicTimeStep not found in WorldInfo.")

    # --- Check TEST_EGG Physics ---
    egg_block = extract_node_block(wbt_content, egg_def)
    physics_enabled = False
    if egg_block:
        if "physics Physics {" in egg_block or "Physics {" in egg_block:
            mass_match = re.search(r'mass\s+([\d.]+)', egg_block)
            if mass_match:
                actual_mass = float(mass_match.group(1))
                # Accept a generous tolerance around 0.05
                if 0.03 <= actual_mass <= 0.07:
                    score += 25
                    physics_enabled = True
                    feedback_parts.append(f"TEST_EGG Physics enabled with correct mass: {actual_mass} kg.")
                else:
                    feedback_parts.append(f"TEST_EGG has Physics but wrong mass: {actual_mass} kg (expected ~0.05).")
            else:
                feedback_parts.append("TEST_EGG has Physics but no mass defined.")
        else:
            feedback_parts.append("TEST_EGG lacks a Physics node (it remains kinematic).")
    else:
        feedback_parts.append(f"DEF {egg_def} node missing from scene.")

    # --- Check Fingertip Conversion & Parameters ---
    index_block = extract_node_block(wbt_content, index_def)
    thumb_block = extract_node_block(wbt_content, thumb_def)

    nodes_converted = False
    index_is_sensor = f"DEF {index_def} TouchSensor" in index_block
    thumb_is_sensor = f"DEF {thumb_def} TouchSensor" in thumb_block

    if index_is_sensor and thumb_is_sensor:
        score += 20
        nodes_converted = True
        feedback_parts.append("Both fingertips correctly converted to TouchSensors.")
    else:
        feedback_parts.append(f"Fingertips not converted properly (Index: {index_is_sensor}, Thumb: {thumb_is_sensor}).")

    # Helper function to check fields inside a block
    def check_field(block: str, regex: str, expected_val) -> bool:
        match = re.search(regex, block)
        if match:
            if isinstance(expected_val, float):
                return abs(float(match.group(1)) - expected_val) < 1e-5
            return match.group(1) == expected_val
        return False

    # Check Sensor Type ("force-3d")
    index_type = check_field(index_block, r'type\s+"([^"]+)"', "force-3d")
    thumb_type = check_field(thumb_block, r'type\s+"([^"]+)"', "force-3d")
    if index_type and thumb_type:
        score += 15
        feedback_parts.append("Sensor types correctly set to 'force-3d'.")
    elif index_is_sensor or thumb_is_sensor:
        feedback_parts.append("TouchSensors created but type is not 'force-3d'.")

    # Check Sensor Resolution (0.001)
    index_res = check_field(index_block, r'resolution\s+([\d.]+)', 0.001)
    thumb_res = check_field(thumb_block, r'resolution\s+([\d.]+)', 0.001)
    if index_res and thumb_res:
        score += 15
        feedback_parts.append("Sensor resolutions correctly set to 0.001.")
    elif index_is_sensor or thumb_is_sensor:
        feedback_parts.append("TouchSensors created but resolution is not 0.001.")

    # --- Final Evaluation ---
    # Strict thresholds to prevent gaming
    key_criteria_met = physics_enabled and nodes_converted
    passed = score >= 70 and key_criteria_met

    if not key_criteria_met and score >= 70:
        feedback_parts.append("FAILED: Key criteria (Egg physics and Sensor conversion) were not fully met.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }