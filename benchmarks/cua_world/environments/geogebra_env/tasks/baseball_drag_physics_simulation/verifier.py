#!/usr/bin/env python3
"""
Verifier for Baseball Drag Physics Simulation.

Scoring (100 points):
- File created: 10 pts
- Vacuum trajectory (Landing ~176.6m): 20 pts
- Drag trajectory command (SolveODE/Sequence): 25 pts
- Drag trajectory accuracy (Landing 115m - 135m): 25 pts
- Points marked on ground: 10 pts
- Dynamic/Calculated nature: 10 pts (Inferred from command usage vs static points)

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_baseball_physics(traj, env_info, task_info):
    """Verify the baseball physics simulation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    vac_expected = metadata.get('vacuum_range_expected', 176.6)
    drag_min = metadata.get('drag_range_min', 115.0)
    drag_max = metadata.get('drag_range_max', 135.0)

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    score = 0
    feedback = []
    
    # 1. File Created (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10).")
    elif result.get("file_found"):
        feedback.append("File found but not created during task (0).")
    else:
        feedback.append("File not found (0).")

    points = result.get("points_on_axis", [])
    
    # 2. Vacuum Trajectory Verification (20 pts)
    # Look for a point near 176.6m
    vacuum_point = None
    for p in points:
        if abs(p['x'] - vac_expected) < 5.0:
            vacuum_point = p
            break
            
    if vacuum_point:
        score += 20
        feedback.append(f"Vacuum landing point found at x={vacuum_point['x']:.1f}m (+20).")
    else:
        feedback.append(f"No vacuum landing point found near {vac_expected}m (0).")

    # 3. Drag Trajectory Method (25 pts)
    # Check if they used ODE solver or Sequence (calculus/numerical methods)
    if result.get("has_ode_command") or result.get("has_sequence_command"):
        score += 25
        feedback.append("Differential equation/Numerical method detected (+25).")
    else:
        feedback.append("No ODE solver or numerical sequence command found (0).")

    # 4. Drag Trajectory Accuracy (25 pts)
    # Look for a point in the drag range [115, 135]
    drag_point = None
    for p in points:
        if drag_min <= p['x'] <= drag_max:
            drag_point = p
            break
    
    if drag_point:
        score += 25
        feedback.append(f"Drag landing point found at x={drag_point['x']:.1f}m (Physically accurate) (+25).")
    else:
        feedback.append(f"No drag landing point found in valid range [{drag_min}m, {drag_max}m] (0).")

    # 5. Landing Points Marked (10 pts)
    # Just checking if we found any points on axis > 10m
    if len(points) >= 2:
        score += 10
        feedback.append(f"Multiple landing points marked ({len(points)}) (+10).")
    elif len(points) == 1:
        score += 5
        feedback.append("One landing point marked (+5).")
    else:
        feedback.append("No landing points marked on x-axis (0).")

    # 6. Dynamic/Calculated (10 pts)
    # If they defined variables and used commands, it's likely dynamic.
    # We check if variables (mass, etc) were defined.
    vars_defined = result.get("variables_defined", [])
    has_physics_vars = False
    # Check for values roughly matching input params (0.145, 0.3, 1.225)
    for v in vars_defined:
        val = v['value']
        if abs(val - 0.145) < 0.01 or abs(val - 0.3) < 0.01 or abs(val - 1.225) < 0.01:
            has_physics_vars = True
            break
            
    if has_physics_vars and (result.get("has_ode_command") or result.get("has_sequence_command")):
        score += 10
        feedback.append("Construction appears dynamic/parametric (+10).")
    else:
        feedback.append("Construction may be hardcoded; physics parameters not clearly identified (0).")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }