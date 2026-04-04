#!/usr/bin/env python3
"""
Verifier for Napoleon's Theorem Task.
Checks for file existence, creation time, geometric correctness (base triangle),
usage of construction commands, and result (Napoleon triangle presence).
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_napoleon_theorem(traj, env_info, task_info):
    """
    Verify the GeoGebra construction of Napoleon's Theorem.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Copy function not available"}

    # Retrieve result JSON
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
    max_score = 100

    # 1. File Creation (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File 'napoleon_theorem.ggb' created successfully.")
    elif result.get("file_exists"):
        feedback.append("File exists but was NOT created during this task (anti-gaming).")
    else:
        feedback.append("File 'napoleon_theorem.ggb' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Base Triangle Coordinates (A, B, C) (20 pts)
    # A(0,0), B(6,0), C(2,5)
    points = result.get("points", [])
    targets = [(0,0), (6,0), (2,5)]
    found_targets = 0
    
    for tx, ty in targets:
        match = False
        for p in points:
            if math.hypot(p['x']-tx, p['y']-ty) < 0.2:
                match = True
                break
        if match:
            found_targets += 1
            
    if found_targets == 3:
        score += 20
        feedback.append("Base triangle vertices correct.")
    elif found_targets > 0:
        score += 10
        feedback.append(f"Found {found_targets}/3 base vertices.")
    else:
        feedback.append("Base triangle vertices (0,0), (6,0), (2,5) not found.")

    # 3. Construction Logic: Equilateral Triangles (20 pts)
    # Look for 'RegularPolygon' commands or at least 4 polygons total (Base + 3 external)
    commands = result.get("commands", [])
    polygons = result.get("polygons", [])
    
    has_regular_polygon = "RegularPolygon" in commands
    has_enough_polygons = len(polygons) >= 4
    
    if has_regular_polygon or has_enough_polygons:
        score += 20
        feedback.append("Construction of external triangles detected.")
    else:
        feedback.append("Missing equilateral triangle construction (RegularPolygon command or multiple polygons).")

    # 4. Centroid Logic (25 pts)
    # Look for 'Centroid' command or implicit centroid points
    # Centroids for the specific triangle:
    # C1 (on AB, down): (3, -1.732)
    # C2 (on BC, right): approx (5.44, 3.65)
    # C3 (on CA, left): approx (-0.77, 3.42)
    centroid_targets = [(3, -1.732), (5.44, 3.65), (-0.77, 3.42)]
    found_centroids = 0
    
    for cx, cy in centroid_targets:
        match = False
        for p in points:
            if math.hypot(p['x']-cx, p['y']-cy) < 0.5: # Generous tolerance
                match = True
                break
        if match:
            found_centroids += 1
            
    has_centroid_cmd = "Centroid" in commands
    
    if found_centroids >= 2:
        score += 25
        feedback.append("Centroid points verified geometrically.")
    elif has_centroid_cmd:
        score += 20 # Credit for using command even if coords slightly off
        feedback.append("Centroid command used.")
    else:
        feedback.append("Centroids not found/calculated.")

    # 5. Napoleon Triangle / Annotation (20 pts)
    # Verified by checking distance ~4.83 between points
    if result.get("napoleon_triangle_found"):
        score += 20
        feedback.append("Napoleon triangle confirmed (equilateral side ~4.83).")
    elif len(result.get("texts", [])) > 0:
        score += 10
        feedback.append("Annotations present, but Napoleon triangle geometry not perfectly confirmed.")
    else:
        feedback.append("Napoleon triangle or annotations missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }