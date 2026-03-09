#!/usr/bin/env python3
"""
Verifier for Exoplanet Scatter Plot task.

Checks:
1. File existence and creation.
2. Existence of 'StarCluster' collection.
3. Accurate representation of CSV data in 3D space:
   - Position (tolerance 0.1)
   - Scale (radius * 0.2, tolerance 0.05)
   - Material Color (Green for habitable, Red for hostile)
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exoplanet_plot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Copy result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic Checks
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output .blend file not found."}
    
    if not result.get("file_new"):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

    scene = result.get("scene_data", {})
    if "error" in scene:
        return {"passed": False, "score": 0, "feedback": f"Blender file analysis failed: {scene['error']}"}

    csv_rows = result.get("csv_data", [])
    if not csv_rows:
        return {"passed": False, "score": 0, "feedback": "Ground truth CSV data missing from result."}

    # Scoring Variables
    score = 0
    feedback = []
    
    # 1. Collection Check (10 pts)
    if scene.get("collection_exists"):
        score += 10
        feedback.append("Collection 'StarCluster' created.")
    else:
        feedback.append("Collection 'StarCluster' NOT found.")

    # 2. Data Matching (90 pts distributed)
    # We iterate through CSV rows and try to find a matching object
    
    scene_objects = scene.get("objects", [])
    matched_count = 0
    correct_pos = 0
    correct_scale = 0
    correct_color = 0
    correct_name = 0
    
    total_planets = len(csv_rows)
    
    # Helper for color distance
    def is_green(rgb):
        # Green channel dominant, Red/Blue low
        return rgb[1] > 0.5 and rgb[0] < 0.4 and rgb[2] < 0.4
    
    def is_red(rgb):
        # Red channel dominant
        return rgb[0] > 0.5 and rgb[1] < 0.4 and rgb[2] < 0.4

    for row in csv_rows:
        pid = row['id']
        rx = float(row['x'])
        ry = float(row['y'])
        rz = float(row['z'])
        r_rad = float(row['radius'])
        r_hab = row['habitable']
        
        target_scale = r_rad * 0.2
        
        # Find closest object
        best_obj = None
        min_dist = 9999.0
        
        for obj in scene_objects:
            ox, oy, oz = obj['location']
            dist = math.sqrt((rx-ox)**2 + (ry-oy)**2 + (rz-oz)**2)
            if dist < min_dist:
                min_dist = dist
                best_obj = obj
        
        # Match if within 0.1 units
        if min_dist < 0.1 and best_obj:
            matched_count += 1
            correct_pos += 1
            
            # Check Name
            if f"Planet_{pid}" in best_obj['name']:
                correct_name += 1
            
            # Check Scale (average of dimensions)
            sx, sy, sz = best_obj['scale']
            avg_scale = (sx + sy + sz) / 3.0
            if abs(avg_scale - target_scale) < 0.05:
                correct_scale += 1
                
            # Check Color
            color = best_obj['color']
            if r_hab == 'Yes':
                if is_green(color):
                    correct_color += 1
            else:
                if is_red(color):
                    correct_color += 1

    # Calculate sub-scores
    # Position: 30 pts
    score_pos = (correct_pos / total_planets) * 30
    score += score_pos
    
    # Scale: 20 pts
    score_scale = (correct_scale / total_planets) * 20
    score += score_scale
    
    # Color: 20 pts
    score_color = (correct_color / total_planets) * 20
    score += score_color
    
    # Name: 10 pts
    score_name = (correct_name / total_planets) * 10
    score += score_name
    
    # Object count check (10 pts)
    # If we matched most of them, we get these points
    if matched_count >= (total_planets * 0.9):
        score += 10
        feedback.append(f"Successfully matched {matched_count}/{total_planets} planets.")
    else:
        feedback.append(f"Only matched {matched_count}/{total_planets} planets.")

    feedback.append(f"Position Acc: {int(score_pos)}/30")
    feedback.append(f"Scale Acc: {int(score_scale)}/20")
    feedback.append(f"Color Logic: {int(score_color)}/20")

    # Final logic
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }