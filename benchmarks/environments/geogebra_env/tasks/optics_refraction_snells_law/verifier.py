#!/usr/bin/env python3
"""
Verifier for Optics Refraction Snell's Law task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optics_refraction_snells_law(traj, env_info, task_info):
    """
    Verify the refraction simulation.
    
    Criteria:
    1. File 'refraction_lab.ggb' created during task (20 pts)
    2. Sliders 'n1' and 'n2' exist (30 pts)
    3. Math logic detected (asin/sin usage) (30 pts)
    4. Geometric elements present (ray/line/segment) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Check
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 20
        feedback.append("File created successfully (+20)")
    elif result.get("file_found"):
        feedback.append("File found but not created during task (0/20)")
    else:
        feedback.append("File 'refraction_lab.ggb' not found (0/20)")

    # 2. Sliders Check
    sliders = result.get("sliders_found", [])
    if "n1" in sliders and "n2" in sliders:
        score += 30
        feedback.append("Sliders 'n1' and 'n2' found (+30)")
    elif "n1" in sliders or "n2" in sliders:
        score += 15
        feedback.append(f"Only found slider(s): {sliders} (+15)")
    else:
        feedback.append("No sliders named 'n1' or 'n2' found (0/30)")

    # 3. Math Logic Check (Snell's Law components)
    math_funcs = result.get("math_functions_used", [])
    has_sin = "sin" in math_funcs
    has_asin = "asin" in math_funcs
    
    if has_sin and has_asin:
        score += 30
        feedback.append("Snell's law logic (sin & asin) detected (+30)")
    elif has_asin:
        score += 20
        feedback.append("Inverse sine detected, assume refraction logic (+20)")
    elif has_sin:
        score += 10
        feedback.append("Sine detected, but missing inverse sine for angle calculation (+10)")
    else:
        feedback.append("No trigonometric functions detected (0/30)")

    # 4. Geometry Check
    geo_count = result.get("geometry_elements", 0)
    if geo_count >= 3:
        score += 20
        feedback.append(f"Geometric construction present ({geo_count} elements) (+20)")
    elif geo_count > 0:
        score += 10
        feedback.append("Minimal geometry found (+10)")
    else:
        feedback.append("No geometric elements (lines/points) found (0/20)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }