#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bent_wire(traj, env_info, task_info):
    """
    Verifies the model_bent_wire_form task.
    Checks file existence, valid geometry, volume, and bounding box.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_vol = metadata.get('target_volume_mm3', 8330)
    vol_tolerance = metadata.get('volume_tolerance_percent', 10)
    target_bbox = [
        metadata.get('bbox_x_length', 106),
        metadata.get('bbox_y_length', 106),
        metadata.get('bbox_z_length', 56)
    ]
    bbox_tolerance = metadata.get('bbox_tolerance_mm', 5)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback_parts.append("File created")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not modified"}

    # 2. Valid Solid (20 pts)
    geo = result.get('geometry', {})
    if geo.get('valid_solid'):
        score += 20
        feedback_parts.append("Valid solid geometry found")
    else:
        return {"passed": False, "score": score, "feedback": "File exists but contains no valid solid object. " + str(geo.get('error', ''))}

    # 3. Volume Check (35 pts)
    # Expected approx 8330 mm3. 
    # Logic: If volume is way off, they probably didn't sweep or used wrong path.
    vol = geo.get('volume', 0)
    vol_min = target_vol * (1 - vol_tolerance/100)
    vol_max = target_vol * (1 + vol_tolerance/100)
    
    if vol_min <= vol <= vol_max:
        score += 35
        feedback_parts.append(f"Volume correct ({vol:.1f} mm³)")
    else:
        feedback_parts.append(f"Volume incorrect ({vol:.1f} vs target {target_vol})")
        # Partial credit if they made something substantial
        if vol > 1000:
            score += 5

    # 4. Bounding Box Check (35 pts)
    # Logic: Ensures the path coordinates were roughly correct.
    # Target dimensions include the wire thickness (path bounds + 6mm).
    bbox = geo.get('bbox', [0,0,0])
    bbox_correct = True
    axis_names = ['X', 'Y', 'Z']
    
    for i in range(3):
        if not (target_bbox[i] - bbox_tolerance <= bbox[i] <= target_bbox[i] + bbox_tolerance):
            bbox_correct = False
            feedback_parts.append(f"BBox {axis_names[i]} mismatch ({bbox[i]:.1f} vs {target_bbox[i]})")
    
    if bbox_correct:
        score += 35
        feedback_parts.append("Dimensions correct")
    else:
        # Partial credit for being close (maybe missed wire radius)
        # If lengths are essentially the path lengths (100, 100, 50) without radius
        path_only = [100, 100, 50]
        is_path_only = all(abs(bbox[i] - path_only[i]) < 5 for i in range(3))
        if is_path_only:
            score += 15
            feedback_parts.append("Dimensions match path but missing wire thickness?")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }