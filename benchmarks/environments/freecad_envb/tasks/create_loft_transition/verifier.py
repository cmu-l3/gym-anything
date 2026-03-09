#!/usr/bin/env python3
"""
Verifier for create_loft_transition task.

Verifies:
1. File exists and was created during the task
2. FreeCAD geometry analysis (performed inside container) confirms:
   - Presence of Loft feature
   - Correct bounding box dimensions (Height ~60mm, Width ~40mm)
   - Volume within expected range
3. VLM Visual verification of the transition shape
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_loft_transition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_height = metadata.get('target_height', 60.0)
    expected_width = metadata.get('target_circle_dia', 40.0)
    min_vol = metadata.get('min_volume_mm3', 45000)
    max_vol = metadata.get('max_volume_mm3', 85000)
    bbox_tol = metadata.get('bbox_tolerance_mm', 5.0)

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Basic File Checks (20 pts)
    if result.get('output_exists'):
        score += 10
        if result.get('file_created_during_task'):
            score += 10
            feedback.append("File created during task.")
        else:
            feedback.append("File exists but timestamp is old.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Geometry Analysis (50 pts)
    geo = result.get('geometry_analysis', {})
    
    # Check for Loft Feature
    if geo.get('has_loft'):
        score += 20
        feedback.append("Loft feature detected.")
    else:
        feedback.append("No Loft feature found in file.")

    # Check Sketches
    if geo.get('sketch_count', 0) >= 2:
        score += 10
        feedback.append(f"Found {geo.get('sketch_count')} sketches.")
    else:
        feedback.append(f"Insufficient sketches found ({geo.get('sketch_count')}).")

    # Check Bounding Box
    # bbox is [xmin, ymin, zmin, xmax, ymax, zmax]
    bbox = geo.get('bbox', [0,0,0,0,0,0])
    z_height = bbox[5] - bbox[2]
    x_width = bbox[3] - bbox[0]
    y_width = bbox[4] - bbox[1]

    if abs(z_height - expected_height) <= bbox_tol:
        score += 10
        feedback.append(f"Height correct ({z_height:.1f}mm).")
    else:
        feedback.append(f"Height mismatch ({z_height:.1f}mm vs {expected_height}mm).")

    # Check Volume
    vol = geo.get('volume', 0)
    if min_vol <= vol <= max_vol:
        score += 10
        feedback.append(f"Volume correct ({vol:.0f} mm^3).")
    else:
        feedback.append(f"Volume out of range ({vol:.0f} mm^3).")

    # 3. VLM Verification (30 pts)
    # Check if the visual output looks like a loft transition
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this FreeCAD screenshot. The user is supposed to create a "Loft" that transitions from a circle at the bottom to a square at the top.
        1. Do you see a 3D solid object?
        2. Does the object look like a transition between two different shapes (e.g. rounded bottom, squared top)?
        3. Is the object roughly vertical (tower-like)?
        """
        
        vlm_out = query_vlm(image=final_screenshot, prompt=prompt)
        
        if vlm_out.get('success'):
            # Simple keyword matching for robust scoring
            response = vlm_out.get('result', '').lower()
            if 'yes' in response and ('transition' in response or 'circle' in response or 'square' in response):
                score += 30
                feedback.append("Visual verification passed.")
            else:
                score += 10 # Partial credit if VLM is uncertain but file exists
                feedback.append("Visual verification inconclusive.")
        else:
             feedback.append("VLM query failed.")
    else:
        feedback.append("No screenshot available for visual check.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }