#!/usr/bin/env python3
"""
Verifier for create_manifold_block task.

Logic:
1. Checks if the output file exists and was created during the task.
2. Reads the geometry analysis performed inside the container (Volume, BBox).
3. Verifies dimensions and volume against the reference geometry.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_manifold_block(traj, env_info, task_info):
    """
    Verify the manifold block creation.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    bbox_tol = metadata.get('bbox_tolerance', 1.0) # mm
    vol_tol_pct = metadata.get('volume_tolerance_percent', 5.0)

    # 2. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Check 1: File Exists (10 pts)
    if result.get('output_exists'):
        score += 10
        feedback.append("File created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Check 2: Anti-gaming (10 pts)
    if result.get('file_created_during_task'):
        score += 10
    else:
        feedback.append("Warning: File timestamp indicates pre-existence or copy.")

    # Check 3: Geometry Analysis
    geo = result.get('geometry', {})
    if not geo.get('success'):
        return {"passed": False, "score": score, "feedback": f"Geometry analysis failed: {geo.get('error', 'Unknown')}"}

    # Check 4: Bounding Box (30 pts)
    # Expected: 60x60x60
    bbox = geo.get('bbox', [0,0,0])
    # Sort dimensions to allow for rotation (though task specifies axes, rotation makes bbox larger if not aligned, 
    # but aligned 60x60x60 is rotation invariant for a cube)
    bbox.sort()
    expected_bbox = [60.0, 60.0, 60.0]
    
    bbox_valid = True
    for i in range(3):
        if abs(bbox[i] - expected_bbox[i]) > bbox_tol:
            bbox_valid = False
            break
            
    if bbox_valid:
        score += 30
        feedback.append("Bounding box correct (60x60x60).")
    else:
        feedback.append(f"Bounding box incorrect: {[round(x,1) for x in bbox]}")

    # Check 5: Volume (50 pts)
    # This verifies the cuts were actually made
    vol = geo.get('volume', 0)
    exp_vol = geo.get('expected_volume', 167000) # Fallback if calc failed, but it should be in JSON
    
    if exp_vol > 0:
        diff_pct = abs(vol - exp_vol) / exp_vol * 100
        if diff_pct <= vol_tol_pct:
            score += 50
            feedback.append(f"Volume correct (Error: {diff_pct:.2f}%).")
        elif diff_pct <= vol_tol_pct * 2:
            score += 25
            feedback.append(f"Volume close but slightly off (Error: {diff_pct:.2f}%).")
        else:
            feedback.append(f"Volume incorrect. Expected ~{int(exp_vol)}, got ~{int(vol)}.")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }