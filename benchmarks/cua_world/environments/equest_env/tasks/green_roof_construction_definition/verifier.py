#!/usr/bin/env python3
"""
Verifier for green_roof_construction_definition task.

Checks:
1. Simulation ran during session.
2. Three specific materials created with correct properties (+/- 1% tolerance).
3. Construction created with correct layers in order.
4. Construction assigned to all roof surfaces.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants (Must match task description)
TARGET_MATERIALS = {
    "GR-Soil-4in": {
        "THICKNESS": 0.333,
        "CONDUCTIVITY": 0.42,
        "DENSITY": 75.0,
        "SPECIFIC-HEAT": 0.25
    },
    "GR-Drainage-Mat": {
        "THICKNESS": 0.042,
        "CONDUCTIVITY": 0.03,
        "DENSITY": 2.5,
        "SPECIFIC-HEAT": 0.35
    },
    "GR-Insulation-R20": {
        "THICKNESS": 0.333,
        "CONDUCTIVITY": 0.017,
        "DENSITY": 1.5,
        "SPECIFIC-HEAT": 0.25
    }
}

TARGET_CONSTRUCTION_LAYERS = ["GR-Soil-4in", "GR-Drainage-Mat", "GR-Insulation-R20"]
RESULT_PATH = "C:\\Users\\Docker\\green_roof_result.json"

def verify_green_roof_construction(traj, env_info, task_info):
    """
    Verify the green roof construction task using the JSON result from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Simulation Check (10 pts)
    if result.get("sim_ran", False):
        score += 10
        feedback_parts.append("Simulation ran (+10)")
    else:
        feedback_parts.append("Simulation did not run")

    # 2. Material Checks (45 pts total, 15 each)
    materials = result.get("materials", {})
    
    for mat_name, targets in TARGET_MATERIALS.items():
        mat_res = materials.get(mat_name, {})
        if not mat_res.get("Exists", False):
            feedback_parts.append(f"Material {mat_name} missing")
            continue
            
        # Check properties
        props_ok = True
        prop_errors = []
        for prop, target_val in targets.items():
            # Keys in result are PascalCase (Thickness) or match the INP keyword
            # Map INP keywords to result keys from PS script
            key_map = {
                "THICKNESS": "Thickness", 
                "CONDUCTIVITY": "Conductivity", 
                "DENSITY": "Density", 
                "SPECIFIC-HEAT": "SpecificHeat"
            }
            res_key = key_map.get(prop)
            val_str = mat_res.get(res_key)
            
            if val_str is None:
                props_ok = False
                prop_errors.append(f"{prop} missing")
                continue
                
            try:
                val = float(val_str)
                # 1% Tolerance
                if abs(val - target_val) > (target_val * 0.01 + 0.001):
                    props_ok = False
                    prop_errors.append(f"{prop} {val}!={target_val}")
            except:
                props_ok = False
                prop_errors.append(f"{prop} invalid")
        
        if props_ok:
            score += 15
            feedback_parts.append(f"{mat_name} correct (+15)")
        else:
            feedback_parts.append(f"{mat_name} incorrect: {', '.join(prop_errors)}")

    # 3. Construction Check (25 pts total)
    # - 10 for existence
    # - 15 for correct layers
    const_res = result.get("construction", {})
    if const_res.get("Exists", False):
        score += 10
        feedback_parts.append("Construction created (+10)")
        
        layers = const_res.get("Layers", [])
        # Normalize layers (strip quotes if present in list, though PS script cleaned them)
        layers = [l.strip().strip('"') for l in layers]
        
        if layers == TARGET_CONSTRUCTION_LAYERS:
            score += 15
            feedback_parts.append("Layers correct (+15)")
        else:
            feedback_parts.append(f"Layers incorrect. Found: {layers}")
    else:
        feedback_parts.append("Construction missing")

    # 4. Assignment Check (20 pts)
    assign_res = result.get("roof_assignments", {})
    total = assign_res.get("total", 0)
    correct = assign_res.get("correct", 0)
    
    if total > 0:
        if correct == total:
            score += 20
            feedback_parts.append(f"All {total} roofs assigned (+20)")
        elif correct > 0:
            partial = int(20 * (correct / total))
            score += partial
            feedback_parts.append(f"{correct}/{total} roofs assigned (+{partial})")
        else:
            feedback_parts.append("No roofs assigned correctly")
    else:
        feedback_parts.append("No roofs found in model (error)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }