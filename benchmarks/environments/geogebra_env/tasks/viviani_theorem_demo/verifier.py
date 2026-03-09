#!/usr/bin/env python3
"""
Verifier for Viviani's Theorem Demo task.

Criteria:
1. File created during task (15 pts)
2. Equilateral triangle constructed (side approx 6) (25 pts)
3. Free point inside triangle (20 pts)
4. Distance commands present (>=3) (25 pts)
5. Text annotation present (15 pts)

Pass threshold: 70 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_viviani_theorem_demo(traj, env_info, task_info):
    """Verify the Viviani's Theorem construction."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. File Check
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File created successfully (+15)")
    else:
        feedback.append("File not found or not created during task (0/15)")

    # 2. Triangle Check
    if result.get("triangle_valid"):
        score += 25
        feedback.append("Equilateral triangle (side ~6) found (+25)")
    else:
        sl = result.get("triangle_side_length", 0)
        feedback.append(f"Valid equilateral triangle not found (avg side: {sl:.2f}) (0/25)")

    # 3. Interior Point Check
    if result.get("point_inside"):
        score += 20
        feedback.append("Interior point found (+20)")
    else:
        feedback.append("No independent point found inside the triangle (0/20)")

    # 4. Distances Check
    num_dist = result.get("num_distance_commands", 0)
    if num_dist >= 3:
        score += 25
        feedback.append(f"Distance measurements found ({num_dist}) (+25)")
    elif num_dist > 0:
        score += 10
        feedback.append(f"Partial distance measurements found ({num_dist}/3) (+10)")
    else:
        feedback.append("No Distance commands found (0/25)")

    # 5. Annotation Check
    if result.get("has_text"):
        score += 15
        feedback.append("Text annotation found (+15)")
    else:
        feedback.append("No text annotation found (0/15)")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }