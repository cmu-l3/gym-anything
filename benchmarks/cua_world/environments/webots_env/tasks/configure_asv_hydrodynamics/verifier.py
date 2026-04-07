#!/usr/bin/env python3
"""
Verifier for configure_asv_hydrodynamics task.

A marine robotics engineer must configure fluid density, immersion properties,
physics center of mass, and add a sonar distance sensor to an ASV model.

Scoring (100 points total):
  - File exists and modified during task: 10 points
  - Fluid density = 1025: 15 points
  - Fluid name = "seawater": 15 points
  - ImmersionProperties fluidName = "seawater": 20 points
  - ImmersionProperties viscousResistanceForceCoefficient = 150: 10 points
  - Physics centerOfMass = [ 0 0 -0.15 ]: 15 points
  - DistanceSensor named "depth_sonar" with type "sonar" and maxRange 50: 15 points

Pass threshold: 75 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_asv_hydrodynamics(traj, env_info, task_info):
    """
    Verify the ASV hydrodynamics world was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/asv_configured.wbt')
    expected_density = metadata.get('expected_fluid_density', 1025)
    
    score = 0
    feedback_parts = []

    # --- Step 1: Check Export Script Result ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_asv_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not parse export JSON: {e}")
        export_result = {}

    if not export_result.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world via File > Save World As."
        }
        
    if not export_result.get("file_created_during_task", True):
        feedback_parts.append("Warning: Output file modification time predates task start.")

    score += 10
    feedback_parts.append("World file saved")

    # --- Step 2: Copy the .wbt file for deep inspection ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

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

    if not wbt_content or len(wbt_content) < 100:
        return {"passed": False, "score": score, "feedback": "World file is empty or corrupted."}

    # --- Extraction Helpers ---
    # Extract the Fluid block
    fluid_block_match = re.search(r'Fluid\s*\{([^}]*)\}', wbt_content, re.DOTALL)
    fluid_content = fluid_block_match.group(1) if fluid_block_match else ""

    # Extract the ImmersionProperties block
    immersion_block_match = re.search(r'ImmersionProperties\s*\{([^}]*)\}', wbt_content, re.DOTALL)
    immersion_content = immersion_block_match.group(1) if immersion_block_match else ""
    
    # Extract the Physics block (specifically for the ASV)
    physics_block_match = re.search(r'physics\s+Physics\s*\{([^}]*)\}', wbt_content, re.DOTALL)
    physics_content = physics_block_match.group(1) if physics_block_match else ""

    # Extract the DistanceSensor block
    distance_sensor_match = re.search(r'DistanceSensor\s*\{([^}]+)\}', wbt_content, re.DOTALL)
    ds_content = distance_sensor_match.group(1) if distance_sensor_match else ""

    # --- Verification 1: Fluid Density (15 pts) ---
    if fluid_content:
        density_match = re.search(r'density\s+([\d.]+)', fluid_content)
        if density_match and float(density_match.group(1)) == expected_density:
            score += 15
            feedback_parts.append(f"Fluid density = {expected_density}")
        else:
            feedback_parts.append("Fluid density not set to 1025")
    else:
        feedback_parts.append("Fluid node missing")

    # --- Verification 2: Fluid Name (15 pts) ---
    if fluid_content:
        name_match = re.search(r'name\s+"([^"]+)"', fluid_content)
        if name_match and name_match.group(1) == "seawater":
            score += 15
            feedback_parts.append("Fluid name = 'seawater'")
        else:
            feedback_parts.append("Fluid name not set to 'seawater'")

    # --- Verification 3: ImmersionProperties fluidName (20 pts) ---
    if immersion_content:
        imm_name_match = re.search(r'fluidName\s+"([^"]+)"', immersion_content)
        if imm_name_match and imm_name_match.group(1) == "seawater":
            score += 20
            feedback_parts.append("ImmersionProperties properly linked to seawater")
        else:
            feedback_parts.append("ImmersionProperties fluidName mismatch")
    else:
        feedback_parts.append("ImmersionProperties node missing")

    # --- Verification 4: ImmersionProperties drag (10 pts) ---
    if immersion_content:
        drag_match = re.search(r'viscousResistanceForceCoefficient\s+([\d.]+)', immersion_content)
        if drag_match and float(drag_match.group(1)) == 150.0:
            score += 10
            feedback_parts.append("viscousResistanceForceCoefficient set to 150")
        else:
            feedback_parts.append("viscousResistanceForceCoefficient incorrect")

    # --- Verification 5: Physics Center of Mass (15 pts) ---
    if physics_content:
        # Match array like: [ 0 0 -0.15 ] with varying spaces
        com_match = re.search(r'centerOfMass\s*\[\s*([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)\s*\]', physics_content)
        if com_match:
            x, y, z = map(float, com_match.groups())
            if abs(x) < 0.01 and abs(y) < 0.01 and abs(z - (-0.15)) < 0.01:
                score += 15
                feedback_parts.append("Virtual keel (centerOfMass) established")
            else:
                feedback_parts.append(f"centerOfMass incorrect (found: {x} {y} {z})")
        else:
            feedback_parts.append("centerOfMass array not correctly formatted or missing")
    else:
        feedback_parts.append("Physics node missing")

    # --- Verification 6: Distance Sensor configuration (15 pts) ---
    if ds_content:
        ds_name = re.search(r'name\s+"([^"]+)"', ds_content)
        ds_type = re.search(r'type\s+"([^"]+)"', ds_content)
        ds_range = re.search(r'maxRange\s+([\d.]+)', ds_content)
        
        valid_sonar = 0
        if ds_name and ds_name.group(1) == "depth_sonar":
            valid_sonar += 5
        if ds_type and ds_type.group(1) == "sonar":
            valid_sonar += 5
        if ds_range and float(ds_range.group(1)) == 50.0:
            valid_sonar += 5
            
        score += valid_sonar
        if valid_sonar == 15:
            feedback_parts.append("Depth sonar successfully installed")
        elif valid_sonar > 0:
            feedback_parts.append("Depth sonar partially configured")
        else:
            feedback_parts.append("Depth sonar properties incorrect")
    else:
        feedback_parts.append("DistanceSensor node missing")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }