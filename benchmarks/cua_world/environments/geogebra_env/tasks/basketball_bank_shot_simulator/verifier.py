#!/usr/bin/env python3
"""
Verifier for Basketball Bank Shot Simulator task.

Scoring Breakdown (100 pts):
- File existence & creation time: 10 pts
- Sliders presence (Velocity, Angle, Restitution): 20 pts
- Physics constants (g=9.8): 20 pts
- Backboard/Hoop geometry (x=4.6): 20 pts
- Trajectory implementation (Curve/If logic): 30 pts

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

def verify_basketball_bank_shot_simulator(traj, env_info, task_info) -> Dict[str, Any]:
    # 1. Setup access to VM files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # 2. Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 3. Verify File Creation (10 pts)
    if result_data.get("file_found") and result_data.get("file_created_during_task"):
        score += 10
        feedback.append("File 'bank_shot.ggb' created successfully (+10).")
    elif result_data.get("file_found"):
        score += 5
        feedback.append("File found but modification time is suspicious (+5).")
    else:
        feedback.append("File 'bank_shot.ggb' not found (0).")

    # 4. Verify Sliders (20 pts)
    # We expect at least 3 sliders (v, angle, e)
    sliders_count = result_data.get("sliders_found", 0)
    slider_labels = result_data.get("slider_labels", [])
    
    if sliders_count >= 3:
        score += 20
        feedback.append(f"Found {sliders_count} sliders ({', '.join(slider_labels[:3])}...) (+20).")
    elif sliders_count > 0:
        score += 10
        feedback.append(f"Found {sliders_count} sliders, expected 3+ (+10).")
    else:
        feedback.append("No numeric sliders found (0).")

    # 5. Verify Physics Constants (20 pts)
    if result_data.get("has_physics_gravity"):
        score += 20
        feedback.append("Gravity constant (9.8) detected (+20).")
    else:
        feedback.append("Gravity constant (9.8) not detected in XML (0).")

    # 6. Verify Backboard/Hoop Geometry (20 pts)
    if result_data.get("has_backboard_geometry"):
        score += 20
        feedback.append("Backboard geometry (x=4.6) detected (+20).")
    else:
        feedback.append("Backboard geometry (x=4.6) not detected (0).")

    # 7. Verify Trajectory Logic (30 pts)
    # This is the core complexity: using Curve() or conditional If() for the bounce
    has_curve = result_data.get("has_curve_command", False)
    has_if = result_data.get("has_conditional", False)
    
    if has_curve or has_if:
        score += 30
        feedback.append("Trajectory logic (Curve/If command) detected (+30).")
    else:
        feedback.append("No parametric 'Curve' command or conditional 'If' logic found for trajectory (0).")

    # 8. Final Scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }