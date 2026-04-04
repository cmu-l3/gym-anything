#!/usr/bin/env python3
"""
Verifier for Geometric Transformations Composition Worksheet.

Checks:
1. File creation/modification during task (Anti-gaming)
2. Presence of original vertices (A, B, C)
3. Usage of Reflect command (or correct reflected coordinates)
4. Usage of Rotate command (or correct rotated coordinates)
5. Presence of text annotations
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60

def verify_transformation_composition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability unavailable"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Result JSON
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
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Timing (15 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File created during task (+15)")
    elif result.get("file_found"):
        feedback.append("File found but modified before task start (0/15)")
    else:
        feedback.append("GeoGebra file not found (0/15)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    points = result.get("points", [])
    commands = result.get("commands", [])
    
    # Helper to check if point exists
    def find_point(target_x, target_y, point_list, tolerance=0.2):
        for p in point_list:
            if abs(p['x'] - target_x) < tolerance and abs(p['y'] - target_y) < tolerance:
                return True
        return False

    # Criterion 2: Original Triangle Vertices (20 pts)
    # Expected: (1, 2), (4, 2), (3, 5)
    orig_targets = metadata.get("original_vertices", [[1, 2], [4, 2], [3, 5]])
    found_orig = sum(1 for tx, ty in orig_targets if find_point(tx, ty, points))
    
    if found_orig == 3:
        score += 20
        feedback.append("Original triangle vertices found (+20)")
    elif found_orig > 0:
        partial = int(20 * (found_orig / 3))
        score += partial
        feedback.append(f"Some original vertices found ({found_orig}/3) (+{partial})")
    else:
        feedback.append("Original triangle vertices missing (0/20)")

    # Criterion 3: Reflection (25 pts)
    # Primary: Check for Reflect command
    # Secondary: Check for reflected points manually
    has_reflect_cmd = result.get("has_reflect_command", False)
    
    refl_targets = metadata.get("reflected_vertices", [[2, 1], [2, 4], [5, 3]])
    found_refl_pts = sum(1 for tx, ty in refl_targets if find_point(tx, ty, points))
    
    if has_reflect_cmd:
        score += 25
        feedback.append("Reflect command used (+25)")
    elif found_refl_pts >= 2:
        # Partial credit for manual placement
        score += 10
        feedback.append("Reflected points found manually (no command used) (+10)")
    else:
        feedback.append("Reflection not performed correctly (0/25)")

    # Criterion 4: Rotation (25 pts)
    has_rotate_cmd = result.get("has_rotate_command", False)
    
    rot_targets = metadata.get("rotated_vertices", [[-2, -1], [-2, -4], [-5, -3]])
    found_rot_pts = sum(1 for tx, ty in rot_targets if find_point(tx, ty, points))
    
    if has_rotate_cmd:
        score += 25
        feedback.append("Rotate command used (+25)")
    elif found_rot_pts >= 2:
        score += 10
        feedback.append("Rotated points found manually (no command used) (+10)")
    else:
        feedback.append("Rotation not performed correctly (0/25)")

    # Criterion 5: Text Annotation (15 pts)
    text_elems = result.get("text_elements", [])
    if len(text_elems) > 0:
        score += 15
        feedback.append("Text annotation found (+15)")
    else:
        feedback.append("No text annotation found (0/15)")

    # Gate Condition: Must use commands or place points to pass
    # If using manual points, max score is 15+20+10+10+15 = 70, which passes.
    # If no transformation attempt, max score is 15+20+15 = 50 (Fail).
    
    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback)
    }