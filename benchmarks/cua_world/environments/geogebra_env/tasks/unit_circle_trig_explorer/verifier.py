#!/usr/bin/env python3
"""
Verifier for Unit Circle Trig Explorer task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_unit_circle_trig_explorer(traj, env_info, task_info):
    """
    Verify the GeoGebra unit circle task.
    
    Criteria:
    1. File created/modified during task (15 pts)
    2. Unit Circle present (20 pts)
    3. Angle Slider present (range approx 0-2pi or 0-360) (15 pts)
    4. Sine Function graphed (20 pts)
    5. Parametric Point on Circle (P = (cos(a), sin(a))) (15 pts)
    6. Parametric Point on Curve (Q = (a, sin(a))) (10 pts)
    7. Text Annotation present (5 pts)
    
    Pass threshold: 70 points
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. File Check (15 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File created successfully (+15)")
    elif result.get("file_found"):
        feedback.append("File found but not modified during task (0)")
    else:
        feedback.append("No output file found (0)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Unit Circle (20 pts)
    if result.get("has_unit_circle"):
        score += 20
        feedback.append("Unit circle identified (+20)")
    else:
        feedback.append("Unit circle missing (0)")

    # 3. Angle Slider (15 pts)
    if result.get("has_angle_slider"):
        score += 15
        feedback.append("Angle slider found (+15)")
    else:
        feedback.append("Appropriate angle slider missing (0)")

    # 4. Sine Function (20 pts)
    if result.get("has_sine_function"):
        score += 20
        feedback.append("Sine function graph found (+20)")
    else:
        feedback.append("Sine function missing (0)")

    # 5. Point on Circle (15 pts)
    if result.get("has_circle_point"):
        score += 15
        feedback.append("Parametric point on circle found (+15)")
    else:
        feedback.append("Point on circle linked to slider missing (0)")

    # 6. Point on Curve (10 pts)
    if result.get("has_curve_point"):
        score += 10
        feedback.append("Point on sine curve found (+10)")
    else:
        feedback.append("Point on curve linked to slider missing (0)")

    # 7. Text (5 pts)
    if result.get("has_text"):
        score += 5
        feedback.append("Text annotation found (+5)")
    else:
        feedback.append("Text annotation missing (0)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }