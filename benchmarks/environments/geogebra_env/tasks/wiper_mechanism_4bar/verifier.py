#!/usr/bin/env python3
"""
Verifier for Wiper Mechanism Task.
Checks if the 4-bar linkage is constructed with correct dimensions and logic.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wiper_mechanism(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criteria 1: File Creation (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10).")
    else:
        feedback.append("File not found or not created during task.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # Criteria 2: Ground Points A(0,0) and D(8,0) (20 pts)
    points = result.get("points_found", [])
    has_origin = any(math.hypot(p[0], p[1]) < 0.1 for p in points)
    has_anchor = any(math.hypot(p[0]-8, p[1]) < 0.1 for p in points)
    
    if has_origin and has_anchor:
        score += 20
        feedback.append("Ground points A(0,0) and D(8,0) found (+20).")
    elif has_origin or has_anchor:
        score += 10
        feedback.append("One ground point found (+10).")
    else:
        feedback.append("Ground points (0,0) and (8,0) missing.")

    # Criteria 3: Dimensional Constraints (30 pts)
    # We look for circles of radius 3 (Crank), 9 (Coupler), 6 (Rocker)
    radii = result.get("circles_radii", [])
    # Allow small tolerance
    has_r3 = any(abs(r - 3.0) < 0.1 for r in radii)
    has_r9 = any(abs(r - 9.0) < 0.1 for r in radii)
    has_r6 = any(abs(r - 6.0) < 0.1 for r in radii)

    # Note: Sometimes the coupler/rocker circles are construction geometry that might be deleted
    # if the agent is advanced, but usually they remain.
    # Alternatively, we check if points exist that satisfy the distance constraints.
    
    constraints_met = 0
    if has_r3: constraints_met += 1
    if has_r9: constraints_met += 1
    if has_r6: constraints_met += 1
    
    score += (constraints_met * 10)
    if constraints_met == 3:
        feedback.append("All link dimensions (3, 9, 6) defined via circles (+30).")
    else:
        feedback.append(f"Found {constraints_met}/3 dimensional constraints defined via circles.")

    # Criteria 4: Construction Logic (Intersect) (20 pts)
    # The key to a working mechanism is using Intersect() on the circles
    if result.get("has_intersect"):
        score += 20
        feedback.append("Mechanism logic (Intersect command) used (+20).")
    else:
        feedback.append("Mechanism logic missing: 'Intersect' command not found. Points may be placed manually (static) rather than constructed (dynamic).")

    # Criteria 5: Visualization (Locus/Trace) (20 pts)
    if result.get("has_locus_or_trace"):
        score += 20
        feedback.append("Motion visualization (Trace/Locus) enabled (+20).")
    else:
        feedback.append("No trace or locus found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }