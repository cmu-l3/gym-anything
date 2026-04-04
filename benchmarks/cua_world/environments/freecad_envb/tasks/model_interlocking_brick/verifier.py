#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interlocking_brick(traj, env_info, task_info):
    """
    Verifies the FreeCAD interlocking brick task.
    
    Criteria:
    1. File exists and created during task.
    2. Geometry analysis confirms correct dimensions (15.8x15.8x11.4).
    3. Geometry analysis confirms correct volume (indicating hollow shell + studs).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load task metadata for tolerances
    metadata = task_info.get('metadata', {})
    target_vol = metadata.get('target_volume_mm3', 1144.0)
    vol_tol = metadata.get('volume_tolerance_mm3', 200.0) # +/- 200 mm3
    
    # Expected dimensions (sorted small to large)
    # 15.8 x 15.8 x 11.4 (9.6 body + 1.8 stud)
    expected_dims = sorted([15.8, 15.8, 11.4])
    dim_tol = metadata.get('bbox_tolerance_mm', 0.5)

    score = 0
    feedback = []
    
    # 1. Get Basic Task Result
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    if not task_result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file brick_2x2.FCStd not found."}

    score += 10 # File exists
    feedback.append("File created")

    if task_result.get("file_created_during_task"):
        score += 10 # Anti-gaming
    else:
        feedback.append("Warning: File timestamp looks old")

    # 2. Get Geometry Analysis
    geo_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/brick_analysis.json", f.name)
            f.seek(0)
            geo_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve geometry analysis: {e}"}

    if geo_data.get("error"):
        return {"passed": False, "score": score, "feedback": f"Geometry analysis failed: {geo_data['error']}"}

    # 3. Evaluate Geometry
    
    # Check Validity
    if geo_data.get("valid"):
        score += 10
        feedback.append("Geometry is valid solid")
    else:
        feedback.append("Geometry contains errors (not a valid solid)")

    # Check Dimensions (Bounding Box)
    # We sort both actual and expected to handle rotation (e.g., Z vs Y axis up)
    actual_dims = sorted(geo_data.get("bbox", [0, 0, 0]))
    dims_match = True
    for i in range(3):
        if abs(actual_dims[i] - expected_dims[i]) > dim_tol:
            dims_match = False
            break
    
    if dims_match:
        score += 30
        feedback.append(f"Dimensions match target ({actual_dims})")
    else:
        feedback.append(f"Dimensions mismatch. Expected ~{expected_dims}, Got {actual_dims}")

    # Check Volume (Proxy for shelling/hollowing)
    # Solid block would be 15.8*15.8*9.6 ~ 2400mm3
    # Hollow brick should be ~1100-1300mm3
    actual_vol = geo_data.get("volume", 0)
    
    if abs(actual_vol - target_vol) < vol_tol:
        score += 30
        feedback.append(f"Volume correct ({actual_vol:.1f} mm³)")
    elif actual_vol > 1800:
        feedback.append(f"Volume too high ({actual_vol:.1f} mm³) - likely not hollowed")
    else:
        feedback.append(f"Volume incorrect ({actual_vol:.1f} mm³)")

    # Check Face Count (Proxy for detailed features)
    # A simple cube has 6 faces. 
    # A brick with 4 studs + hollow + tube will have many faces (>20).
    faces = geo_data.get("faces", 0)
    if faces > 15:
        score += 10
        feedback.append("Feature complexity detected")
    else:
        feedback.append("Geometry too simple (missing studs/shell?)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }