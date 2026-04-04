#!/usr/bin/env python3
"""
Verifier for Bicycle Geometry Trail Calculator task.

Scoring (100 points):
- File created during task: 10 pts
- Wheel Constructed (Radius 370): 20 pts
- Steering Axis Angle (67 deg): 20 pts
- Steering Axis Offset (44 mm): 25 pts
- Trail Measured (~109 mm): 25 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_bicycle_geometry_trail_calculator(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. File existence (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created (+10)")
    elif result.get('file_found'):
        feedback_parts.append("File found but not created during task (0/10)")
    else:
        feedback_parts.append("File not found (0/10)")

    # 2. Wheel Radius 370 (20 pts)
    if result.get('has_radius_370'):
        score += 20
        feedback_parts.append("Wheel radius 370mm verified (+20)")
    else:
        feedback_parts.append("Wheel radius 370mm not found (0/20)")

    # 3. Head Angle 67 (20 pts)
    if result.get('has_angle_67'):
        score += 20
        feedback_parts.append("Head angle 67° verified (+20)")
    else:
        feedback_parts.append("Head angle 67° not found (0/20)")

    # 4. Fork Offset 44 (25 pts)
    # Stronger check: if trail is correct, offset implies correctness
    trail_val = result.get('measured_trail', 0.0)
    has_offset = result.get('has_offset_44')
    
    # Tolerance for trail
    expected_trail = 109.2
    trail_correct = abs(trail_val - expected_trail) < 2.0
    
    if has_offset:
        score += 25
        feedback_parts.append("Fork offset 44mm verified (+25)")
    elif trail_correct:
        # If trail is correct, offset must be correct implicitly
        score += 25
        feedback_parts.append("Fork offset inferred correct from trail (+25)")
    else:
        feedback_parts.append("Fork offset 44mm not found (0/25)")

    # 5. Trail Measurement (25 pts)
    if trail_correct:
        score += 25
        feedback_parts.append(f"Trail measured correctly ({trail_val:.1f} mm) (+25)")
    else:
        if trail_val > 0:
            feedback_parts.append(f"Trail measurement incorrect ({trail_val:.1f} mm, expected ~109.2) (0/25)")
        else:
            feedback_parts.append("Trail measurement not found (0/25)")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }