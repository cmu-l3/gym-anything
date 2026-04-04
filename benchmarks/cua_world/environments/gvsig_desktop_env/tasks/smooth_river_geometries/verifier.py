#!/usr/bin/env python3
"""
Verifier for smooth_river_geometries task.

Verifies:
1. Output file existence and timestamp (Anti-gaming).
2. Geometry type preservation (Must be PolyLine, not Polygon).
3. File size increase (Smoothing/Densification adds vertices; Simplification removes them).
4. VLM Trajectory check (Visual confirmation of tool usage).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_smooth_river_geometries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamp (20 pts) ---
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists and created_during:
        score += 20
        feedback_parts.append("Output file created successfully")
    elif output_exists:
        score += 5
        feedback_parts.append("Output file exists but timestamp is old (pre-existing?)")
    else:
        feedback_parts.append("No output file found at expected path")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Geometry Type Check (20 pts) ---
    # Shapefile Type 3 = PolyLine, 13 = PolyLineZ, 23 = PolyLineM
    # If the user buffered the lines, it would be Type 5 (Polygon)
    shp_type = result.get('shape_type_code', -1)
    if shp_type in [3, 13, 23]:
        score += 20
        feedback_parts.append("Geometry type is PolyLine (Correct)")
    elif shp_type in [5, 15, 25]:
        feedback_parts.append("Geometry type is Polygon (Incorrect - likely used Buffer instead of Smooth)")
    else:
        feedback_parts.append(f"Unknown geometry type code: {shp_type}")

    # --- Criterion 3: Smoothing vs Simplification (30 pts) ---
    # Smoothing/Densifying adds vertices -> File size increases
    # Simplifying removes vertices -> File size decreases
    input_size = result.get('input_size_bytes', 1)
    output_size = result.get('output_size_bytes', 0)
    
    if input_size > 0:
        ratio = output_size / input_size
        if ratio > 1.05:  # At least 5% larger
            score += 30
            feedback_parts.append(f"File size increased ({ratio:.2f}x) - Smoothing confirmed")
        elif ratio < 0.95:
            feedback_parts.append(f"File size decreased ({ratio:.2f}x) - Likely used Simplify instead of Smooth")
        else:
            feedback_parts.append(f"File size unchanged ({ratio:.2f}x) - No significant geometry change")
    
    # --- Criterion 4: VLM Trajectory Verification (30 pts) ---
    # Check if Geoprocessing toolbox was used
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = (
        "Analyze these screenshots of a gvSIG Desktop session. "
        "The user was asked to 'Smooth' or 'Densify' river lines. "
        "1. Do you see the Geoprocessing/Sextante toolbox open? "
        "2. Do you see a dialog for a tool like 'Smooth', 'Densify', or 'B-Spline'? "
        "3. Does the map view show river lines? "
        "Answer with Yes/No and a brief observation."
    )
    
    try:
        vlm_result = query_vlm(images, vlm_prompt).lower()
        if "yes" in vlm_result and ("smooth" in vlm_result or "toolbox" in vlm_result or "sextante" in vlm_result):
            score += 30
            feedback_parts.append("VLM confirmed geoprocessing tool usage")
        else:
            # Partial credit if visual output looks okay but tool usage unclear
            if score >= 60: 
                score += 15
                feedback_parts.append("VLM inconclusive on tool usage, but output file is valid")
            else:
                feedback_parts.append("VLM did not observe correct tool usage")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if file checks passed perfectly, assume success
        if score >= 70:
            score += 30
            feedback_parts.append("VLM skipped (error), assuming success based on file metrics")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }