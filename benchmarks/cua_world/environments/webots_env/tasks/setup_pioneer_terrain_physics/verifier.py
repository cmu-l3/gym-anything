#!/usr/bin/env python3
"""
Verifier for setup_pioneer_terrain_physics task.

A field robotics engineer must configure physics parameters for a Pioneer 3-AT robot
simulation on agricultural terrain. Requires:
  - Setting robot body mass to 12.5 kg (Pioneer 3-AT real spec)
  - Adding ContactProperties for wheel-terrain dynamics (coulombFriction=0.7)

Scoring (100 points total):
  - File saved at correct path: 10 points
  - Robot body Physics mass in range [10.0, 15.0] (centered on 12.5 kg): 30 points
  - ContactProperties node present in world: 30 points
  - ContactProperties friction value in range [0.5, 0.9]: 30 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_setup_pioneer_terrain_physics(traj, env_info, task_info):
    """
    Verify that the Pioneer 3-AT physics configuration world has been correctly saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/pioneer_terrain.wbt')
    expected_mass = metadata.get('expected_robot_mass', 12.5)
    expected_friction = metadata.get('expected_coulomb_friction', 0.7)

    score = 0
    feedback_parts = []

    # --- Copy the .wbt file independently ---
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

    # --- Check file existence ---
    if not wbt_content or len(wbt_content) < 100:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world with File > Save World As."
        }

    score += 10
    feedback_parts.append("World file saved at correct path")

    # --- Check robot body mass ---
    # Find the PIONEER_ROBOT's Physics block and extract its mass
    # The robot body mass is inside the top-level Physics block (not wheel physics)
    robot_mass_found = False

    # Try to find PIONEER_ROBOT section and get body mass
    pioneer_idx = wbt_content.find('PIONEER_ROBOT')
    search_start = pioneer_idx if pioneer_idx != -1 else 0

    # Look for physics Physics { ... mass X ... } blocks in the robot
    # We search within a reasonable window after the robot DEF
    segment = wbt_content[search_start:search_start + 3000] if search_start < len(wbt_content) else wbt_content

    # Find all mass values in the file
    all_mass_matches = re.findall(r'mass\s+([\d.]+)', wbt_content)

    if all_mass_matches:
        # Find the largest mass (robot body is heavier than wheels)
        masses = [float(m) for m in all_mass_matches]
        max_mass = max(masses)

        if 10.0 <= max_mass <= 15.0:
            score += 30
            feedback_parts.append(
                f"Robot body mass correctly set to {max_mass:.1f} kg "
                f"(within acceptable range for Pioneer 3-AT spec of {expected_mass} kg)"
            )
            robot_mass_found = True
        elif max_mass > 0.1:
            feedback_parts.append(
                f"Largest mass in world is {max_mass:.1f} kg, "
                f"expected ~{expected_mass} kg (Pioneer 3-AT spec). "
                "Check that the PIONEER_ROBOT body Physics node mass is set correctly."
            )
        else:
            feedback_parts.append(
                f"Robot mass values found: {masses[:3]}, none in expected range [10.0, 15.0] kg"
            )
    else:
        feedback_parts.append(
            "No Physics mass values found in saved world. "
            "The robot body Physics node may not have a mass set."
        )

    # --- Check ContactProperties presence ---
    has_contact_props = 'ContactProperties' in wbt_content
    if has_contact_props:
        score += 30
        feedback_parts.append("ContactProperties node found in world")
    else:
        feedback_parts.append(
            "No ContactProperties node found. "
            "Add a ContactProperties node to WorldInfo for wheel-terrain contact dynamics."
        )

    # --- Check ContactProperties friction value ---
    if has_contact_props:
        friction_matches = re.findall(r'coulombFriction\s+([\d.]+)', wbt_content)
        if friction_matches:
            actual_friction = float(friction_matches[0])
            if 0.5 <= actual_friction <= 0.9:
                score += 30
                feedback_parts.append(
                    f"ContactProperties coulombFriction={actual_friction:.2f} "
                    f"is within acceptable range [0.5, 0.9] for terrain"
                )
            else:
                feedback_parts.append(
                    f"ContactProperties coulombFriction={actual_friction:.2f} "
                    f"is outside expected range [0.5, 0.9] for agricultural terrain"
                )
        else:
            # Check for alternate friction field names
            softness_match = re.search(r'ContactProperties\s*\{', wbt_content)
            if softness_match:
                feedback_parts.append(
                    "ContactProperties node found but coulombFriction field not detected. "
                    "Ensure coulombFriction is set (expected ~0.7 for gravel/packed dirt)."
                )

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "debug": {
            "wbt_size": len(wbt_content),
            "has_contact_props": has_contact_props,
        }
    }
