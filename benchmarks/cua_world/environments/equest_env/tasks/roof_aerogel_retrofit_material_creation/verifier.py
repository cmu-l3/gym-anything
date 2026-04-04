#!/usr/bin/env python3
"""
Verifier for roof_aerogel_retrofit_material_creation task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_roof_aerogel_retrofit(traj, env_info, task_info):
    """
    Verifies:
    1. Simulation ran during session.
    2. 'Aerogel Blanket' material created with correct properties.
    3. 'Roof Construction' uses the new material.
    4. Thickness is set correctly (approx 0.167).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    exp_cond = metadata.get('expected_conductivity', 0.008)
    exp_dens = metadata.get('expected_density', 10.0)
    exp_sh = metadata.get('expected_specific_heat', 0.25)
    exp_thick = metadata.get('target_thickness', 0.167)

    # Fetch result from VM
    result_path = "C:\\Users\\Docker\\task_result.json"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Simulation Check (10 pts)
    if result.get('sim_file_new', False):
        score += 10
        feedback.append("Simulation ran successfully (+10).")
    else:
        feedback.append("Simulation did not run during the session.")

    # 2. Material Existence (20 pts)
    if result.get('material_exists', False):
        score += 20
        feedback.append("'Aerogel Blanket' material created (+20).")
    else:
        feedback.append("'Aerogel Blanket' material not found.")
        # If material missing, critical failure for other props
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Material Properties (30 pts total)
    # Conductivity (20 pts)
    act_cond = float(result.get('material_conductivity', -1))
    if abs(act_cond - exp_cond) < 0.001:
        score += 20
        feedback.append("Conductivity correct (+20).")
    else:
        feedback.append(f"Conductivity incorrect: got {act_cond}, expected {exp_cond}.")

    # Density & Specific Heat (10 pts)
    act_dens = float(result.get('material_density', -1))
    act_sh = float(result.get('material_specific_heat', -1))
    
    props_ok = True
    if abs(act_dens - exp_dens) > 1.0: props_ok = False
    if abs(act_sh - exp_sh) > 0.05: props_ok = False
    
    if props_ok:
        score += 10
        feedback.append("Density and Specific Heat correct (+10).")
    else:
        feedback.append("Density or Specific Heat incorrect.")

    # 4. Construction Assignment (20 pts)
    if result.get('roof_uses_material', False):
        score += 20
        feedback.append("Roof Construction updated with new material (+20).")
    else:
        feedback.append("Roof Construction does not use 'Aerogel Blanket'.")

    # 5. Thickness Check (20 pts)
    act_thick = float(result.get('layer_thickness', -1))
    if abs(act_thick - exp_thick) < 0.005:
        score += 20
        feedback.append("Layer thickness correct (+20).")
    else:
        feedback.append(f"Layer thickness incorrect: got {act_thick}, expected {exp_thick}.")

    passed = score >= 70 and result.get('material_exists') and result.get('roof_uses_material')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }