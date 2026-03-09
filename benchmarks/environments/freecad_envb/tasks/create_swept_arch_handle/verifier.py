#!/usr/bin/env python3
"""
Verifier for create_swept_arch_handle task.

Verifies:
1. Output files exist (FCStd and STEP)
2. Files were created during the task (anti-gaming)
3. Geometry is a valid solid
4. Volume matches expected Half-Torus volume (~17765 mm3)
5. Bounding box matches expected dimensions (~112x12x62 mm)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_swept_arch_handle(traj, env_info, task_info):
    """
    Verify the swept arch handle creation.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    expected_volume = ground_truth.get('volume_mm3', 17765.3)
    vol_tolerance = ground_truth.get('volume_tolerance', 0.20)
    
    expected_bbox = ground_truth.get('bbox_dims_mm', [112.0, 12.0, 62.0])
    bbox_tolerance = ground_truth.get('bbox_tolerance', 0.25)

    # 2. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Files Check (20 pts)
    fcstd_exists = result.get('fcstd_exists', False)
    step_exists = result.get('step_exists', False)
    files_new = result.get('files_created_during_task', False)
    
    if fcstd_exists: 
        score += 10
        feedback_parts.append("FCStd file created")
    if step_exists: 
        score += 10
        feedback_parts.append("STEP file created")
        
    if not (fcstd_exists or step_exists):
        return {"passed": False, "score": 0, "feedback": "No output files found"}
        
    if not files_new:
        feedback_parts.append("Warning: Files have old timestamps (possible pre-existing files)")
        score = max(0, score - 10) # Penalize but verify geometry first

    # Geometry Analysis (80 pts)
    geo = result.get('geometry', {})
    
    # Error check
    if geo.get('error'):
        return {"passed": False, "score": score, "feedback": f"Geometry analysis failed: {geo['error']}"}

    # Validity (15 pts)
    if geo.get('valid_shape', False):
        score += 15
        feedback_parts.append("Shape is valid")
    else:
        feedback_parts.append("Shape is invalid")

    # Solid check (10 pts)
    # Accept Solid, CompSolid, or Compound if it contains 1 solid
    shape_type = geo.get('shape_type', 'Unknown')
    num_solids = geo.get('num_solids', 0)
    
    if num_solids == 1 and ("Solid" in shape_type or "Compound" in shape_type):
        score += 10
        feedback_parts.append("Single solid body found")
    else:
        feedback_parts.append(f"Expected 1 solid, found {num_solids} ({shape_type})")

    # Volume Check (30 pts)
    measured_vol = geo.get('volume', 0)
    if expected_volume > 0:
        error_ratio = abs(measured_vol - expected_volume) / expected_volume
        if error_ratio <= vol_tolerance:
            score += 30
            feedback_parts.append(f"Volume correct ({measured_vol:.0f} mm3)")
        elif error_ratio <= vol_tolerance * 2:
            score += 10 # Partial credit
            feedback_parts.append(f"Volume approx correct ({measured_vol:.0f} mm3)")
        else:
            feedback_parts.append(f"Volume incorrect (Expected ~{expected_volume:.0f}, Got {measured_vol:.0f})")
    
    # Bounding Box Check (25 pts)
    # We check if the sorted dimensions match (to account for rotation)
    measured_bbox = sorted(geo.get('bbox', [0, 0, 0]))
    target_bbox = sorted(expected_bbox)
    
    bbox_match = True
    for m, t in zip(measured_bbox, target_bbox):
        if t == 0: continue
        if abs(m - t) / t > bbox_tolerance:
            bbox_match = False
            break
            
    if bbox_match:
        score += 25
        feedback_parts.append("Dimensions correct")
    else:
        feedback_parts.append(f"Dimensions mismatch (Got {measured_bbox}, Expected approx {target_bbox})")

    # 4. Final Result
    passed = score >= 60 and geo.get('valid_shape', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }