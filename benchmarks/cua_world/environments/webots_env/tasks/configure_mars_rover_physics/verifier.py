#!/usr/bin/env python3
"""
Verifier for configure_mars_rover_physics task.

A planetary robotics engineer must reconfigure simulation parameters to match
the Mars environment and rover hardware specifications.

Scoring (100 points total):
  - File exists and valid format: 10 points
  - Mars gravity (3.0-4.5): 20 points
  - Timestep <= 32: 15 points
  - Camera width = 1024: 15 points
  - Camera height = 768: 10 points
  - Rover mass (150-210 kg): 15 points
  - ContactProperties node with friction 0.2-0.6: 15 points

Pass threshold: 70 points
"""

import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_configure_mars_rover_physics(traj, env_info, task_info):
    """
    Verify the Mars rover world was correctly configured and saved.
    Copies the .wbt file from the VM and checks for parameter values.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/mars_rover.wbt')

    score = 0
    feedback_parts = []
    
    # --- Independently copy and parse the .wbt file ---
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

    # --- Step 1: Check file existence and basic validity (10 pts) ---
    if not wbt_content or len(wbt_content) < 500:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path} or file is too small. "
                        "You must save the configured world using File > Save World As."
        }
        
    if "MARS_ROVER" not in wbt_content or "WorldInfo" not in wbt_content:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Saved file does not appear to be the correct Mars rover simulation world."
        }

    score += 10
    feedback_parts.append("File exists and format is valid")

    # --- Step 2: Check Gravity (20 pts) ---
    gravity_match = re.search(r'gravity\s+([\d.]+)', wbt_content)
    if gravity_match:
        actual_gravity = float(gravity_match.group(1))
        if 3.0 <= actual_gravity <= 4.5:
            score += 20
            feedback_parts.append(f"Gravity={actual_gravity} m/s² matches Mars expected range")
        else:
            feedback_parts.append(f"Gravity={actual_gravity} is incorrect (expected ~3.72 for Mars)")
    else:
        feedback_parts.append("Gravity field not found in WorldInfo")

    # --- Step 3: Check Timestep (15 pts) ---
    timestep_match = re.search(r'basicTimeStep\s+(\d+)', wbt_content)
    if timestep_match:
        actual_timestep = int(timestep_match.group(1))
        if actual_timestep <= 32:
            score += 15
            feedback_parts.append(f"basicTimeStep={actual_timestep} is correct (<=32ms)")
        else:
            feedback_parts.append(f"basicTimeStep={actual_timestep} is too coarse (expected 16)")
    else:
        feedback_parts.append("basicTimeStep field not found")

    # --- Step 4: Check Camera Width & Height (25 pts total) ---
    camera_idx = wbt_content.find('DEF nav_camera Camera')
    if camera_idx == -1:
        camera_idx = wbt_content.find('"nav_camera"')
        
    if camera_idx != -1:
        # Search for width and height in the segment following the camera
        cam_segment = wbt_content[camera_idx:camera_idx + 400]
        
        width_match = re.search(r'width\s+(\d+)', cam_segment)
        if width_match:
            actual_width = int(width_match.group(1))
            if actual_width == 1024:
                score += 15
                feedback_parts.append("Camera width correctly set to 1024")
            else:
                feedback_parts.append(f"Camera width={actual_width} (expected 1024)")
        else:
            feedback_parts.append("Camera width not found")

        height_match = re.search(r'height\s+(\d+)', cam_segment)
        if height_match:
            actual_height = int(height_match.group(1))
            if actual_height == 768:
                score += 10
                feedback_parts.append("Camera height correctly set to 768")
            else:
                feedback_parts.append(f"Camera height={actual_height} (expected 768)")
        else:
            feedback_parts.append("Camera height not found")
    else:
        feedback_parts.append("nav_camera node not found")

    # --- Step 5: Check Rover Mass (15 pts) ---
    rover_idx = wbt_content.find('DEF MARS_ROVER')
    if rover_idx != -1:
        physics_idx = wbt_content.find('Physics {', rover_idx)
        if physics_idx != -1:
            phys_segment = wbt_content[physics_idx:physics_idx + 200]
            mass_match = re.search(r'mass\s+([\d.]+)', phys_segment)
            if mass_match:
                actual_mass = float(mass_match.group(1))
                if 150.0 <= actual_mass <= 210.0:
                    score += 15
                    feedback_parts.append(f"Rover mass={actual_mass} kg is correct")
                else:
                    feedback_parts.append(f"Rover mass={actual_mass} kg (expected ~180.0)")
            else:
                feedback_parts.append("Rover Physics mass field not found")
        else:
            feedback_parts.append("Rover Physics node not found")
    else:
        feedback_parts.append("MARS_ROVER node not found")

    # --- Step 6: Check ContactProperties (15 pts) ---
    if 'ContactProperties' in wbt_content:
        # Friction can be listed as: coulombFriction [ 0.4 ] or coulombFriction 0.4
        friction_match = re.search(r'coulombFriction\s*(?:\[\s*)?([\d.]+)', wbt_content)
        if friction_match:
            actual_friction = float(friction_match.group(1))
            if 0.2 <= actual_friction <= 0.6:
                score += 15
                feedback_parts.append(f"ContactProperties coulombFriction={actual_friction} is correct")
            else:
                feedback_parts.append(f"ContactProperties coulombFriction={actual_friction} (expected ~0.4)")
        else:
            feedback_parts.append("coulombFriction field not found in ContactProperties")
    else:
        feedback_parts.append("ContactProperties node not added to WorldInfo")

    # --- Final Evaluation ---
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }