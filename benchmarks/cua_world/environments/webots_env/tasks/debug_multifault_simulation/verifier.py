#!/usr/bin/env python3
"""
Verifier for debug_multifault_simulation task.

A senior robotics simulation engineer must discover and fix 3 planted errors in a
Webots world (wrong basicTimeStep, zero gravity, zero robot mass). No errors are
identified in the task description — the agent must find them independently.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - basicTimeStep <= 64 (was 256): 30 points
  - gravity >= 9.0 (was 0.0): 30 points
  - All robot Physics mass values > 0.1 (at least one was 0.0): 30 points

Pass threshold: 70 points

Note: Range-based verification is used because this is a very_hard task where the
agent must choose appropriate correction values independently. Any physically correct
value (e.g., timestep 8-64ms, gravity 9.5-10.0, mass > 0.1 kg) is accepted.
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_debug_multifault_simulation(traj, env_info, task_info):
    """
    Verify that all simulation configuration errors have been identified and fixed.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/fixed_simulation.wbt')
    verification = metadata.get('verification_ranges', {
        'basicTimeStep_max': 64,
        'gravity_min': 9.0,
        'mass_min': 0.1
    })

    score = 0
    feedback_parts = []
    subscores = {}

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
    if not wbt_content or len(wbt_content) < 200:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Output file not found at {output_path}. "
                "The fixed simulation must be saved using File > Save World As."
            )
        }

    score += 10
    feedback_parts.append("Fixed simulation saved at correct path")
    subscores["file_exists"] = True

    # --- Check Error 1: basicTimeStep ---
    timestep_match = re.search(r'basicTimeStep\s+(\d+)', wbt_content)
    if timestep_match:
        actual_timestep = int(timestep_match.group(1))
        max_timestep = verification.get('basicTimeStep_max', 64)
        if actual_timestep <= max_timestep:
            score += 30
            feedback_parts.append(
                f"basicTimeStep fixed: {actual_timestep}ms is acceptable "
                f"(<= {max_timestep}ms for robot simulation accuracy)"
            )
            subscores["timestep_fixed"] = True
        else:
            feedback_parts.append(
                f"basicTimeStep={actual_timestep}ms is still too slow for accurate simulation "
                f"(was 256ms, should be <= {max_timestep}ms). "
                "Find WorldInfo in the scene tree and reduce basicTimeStep."
            )
            subscores["timestep_fixed"] = False
    else:
        feedback_parts.append("basicTimeStep not found in saved world")
        subscores["timestep_fixed"] = False

    # --- Check Error 2: gravity ---
    gravity_match = re.search(r'gravity\s+([\d.]+)', wbt_content)
    if gravity_match:
        actual_gravity = float(gravity_match.group(1))
        min_gravity = verification.get('gravity_min', 9.0)
        if actual_gravity >= min_gravity:
            score += 30
            feedback_parts.append(
                f"Gravity fixed: {actual_gravity} m/s² is physically correct "
                f"(was 0.0, Earth gravity is ~9.81 m/s²)"
            )
            subscores["gravity_fixed"] = True
        else:
            feedback_parts.append(
                f"Gravity={actual_gravity} m/s² is still incorrect "
                f"(was 0.0, expected Earth gravity ~9.81 m/s²). "
                "Find WorldInfo in the scene tree and set gravity to 9.81."
            )
            subscores["gravity_fixed"] = False
    else:
        feedback_parts.append(
            "Gravity field not found in saved world. "
            "WorldInfo gravity should be set to ~9.81 m/s²."
        )
        subscores["gravity_fixed"] = False

    # --- Check Error 3: robot Physics mass values ---
    mass_matches = re.findall(r'mass\s+([\d.]+)', wbt_content)
    min_mass = verification.get('mass_min', 0.1)

    if mass_matches:
        masses = [float(m) for m in mass_matches]
        # Check that no mass is zero or near-zero
        invalid_masses = [m for m in masses if m <= min_mass]

        if not invalid_masses:
            score += 30
            feedback_parts.append(
                f"All robot Physics mass values are positive (min found: {min(masses):.3f} kg). "
                "Zero-mass robot fixed."
            )
            subscores["mass_fixed"] = True
        else:
            feedback_parts.append(
                f"Some mass values are still too low: {invalid_masses[:3]}. "
                "One robot has mass=0 (or near-zero) causing physics errors. "
                "Find the robot's Physics node and set a realistic mass (e.g., > 1.0 kg)."
            )
            subscores["mass_fixed"] = False
    else:
        # No mass fields found — may mean agent removed physics entirely
        feedback_parts.append(
            "No Physics mass values found in saved world. "
            "Ensure at least the main robot(s) have Physics nodes with positive mass values."
        )
        subscores["mass_fixed"] = False

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No criteria met",
        "subscores": subscores,
        "debug": {
            "wbt_size": len(wbt_content),
            "errors_found_by_agent": sum([
                subscores.get("timestep_fixed", False),
                subscores.get("gravity_fixed", False),
                subscores.get("mass_fixed", False)
            ])
        }
    }
