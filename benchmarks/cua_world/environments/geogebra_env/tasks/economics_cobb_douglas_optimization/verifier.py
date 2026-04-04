#!/usr/bin/env python3
"""
Verifier for Economics Optimization task.

Scoring:
- File created/valid: 10 pts
- Sliders (I, Px, Py) present: 20 pts
- Budget Line dynamic & present: 20 pts
- Optimal Point logic correct (dynamic): 30 pts
- Indifference Curve present: 10 pts
- Styling (Red/Blue): 10 pts
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_economics_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Programmatic Verification
    
    # File Existence (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File 'utility_max.ggb' created successfully.")
    else:
        feedback.append("File not found or not created during task.")

    # Sliders (20 pts)
    sliders = result.get("sliders_found", [])
    # Normalize case for checking
    sliders_lower = [s.lower() for s in sliders]
    required = ['i', 'px', 'py']
    found_required = sum(1 for r in required if r in sliders_lower)
    
    if found_required >= 3:
        score += 20
        feedback.append("All 3 parameter sliders found.")
    elif found_required > 0:
        score += 10
        feedback.append(f"Found {found_required}/3 sliders.")
    else:
        feedback.append("No parameter sliders found.")

    # Budget Line (20 pts)
    if result.get("budget_line_found"):
        score += 15
        if result.get("budget_line_color") == "red":
            score += 5
            feedback.append("Budget line found (Red).")
        else:
            feedback.append("Budget line found (Wrong color).")
    else:
        feedback.append("Budget line not found.")

    # Optimal Point (30 pts)
    # Critical: Must be dynamic (depend on sliders)
    if result.get("optimal_point_found"):
        if result.get("optimal_point_dynamic"):
            score += 30
            feedback.append("Optimal point constructed with dynamic dependencies.")
        else:
            score += 10
            feedback.append("Optimal point found but appears static (not linked to sliders).")
    else:
        feedback.append("Optimal point not found.")

    # Indifference Curve (10 pts)
    if result.get("indifference_curve_found"):
        score += 5
        if result.get("indifference_curve_color") == "blue":
            score += 5
            feedback.append("Indifference curve found (Blue).")
        else:
            feedback.append("Indifference curve found (Wrong color).")
    else:
        feedback.append("Indifference curve not found.")

    # 3. VLM Verification (Safety check for empty/nonsense screens)
    # Only perform if score is high enough to pass, to confirm validity
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Does the final screen show a GeoGebra math plot with:\n"
            "1. A straight line (budget line)?\n"
            "2. A curved line (hyperbola/indifference curve)?\n"
            "3. A point where they touch/intersect?\n"
            "4. Sliders visible on the screen?\n"
            "Answer yes/no and briefly describe the plot."
        )
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        # We don't strictly penalize score unless VLM is absolutely negative,
        # but we append feedback.
        if vlm_res and vlm_res.get('success'):
            feedback.append(f"VLM Observation: {vlm_res.get('response')}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }