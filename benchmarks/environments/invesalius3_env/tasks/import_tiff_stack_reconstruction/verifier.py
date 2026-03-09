#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_import_tiff_stack_reconstruction(traj, env_info, task_info):
    """
    Verifies that the agent imported the TIFF stack and calibrated it correctly.
    
    Criteria:
    1. STL file exists and is valid.
    2. STL was created during the task.
    3. STL contains non-trivial geometry (>1000 triangles).
    4. Bounding box dimensions match the calibration target (0.957mm spacing)
       instead of the default (1.0mm spacing).
       
    Target Width (X): ~490mm (0.957 * 512)
    Default Width (X): ~512mm (1.0 * 512)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    target_width = metadata.get('target_width_mm', 490.0)
    tolerance = metadata.get('target_tolerance_mm', 5.0)
    
    # Retrieve result from container
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

    # Scoring
    score = 0
    feedback_parts = []
    
    # Check 1: File Existence & Validity (40 pts)
    if result.get("exists") and result.get("valid_stl"):
        score += 30
        feedback_parts.append("Valid STL file created")
        
        if result.get("created_during_task"):
            score += 10
            feedback_parts.append("New file")
        else:
            feedback_parts.append("Old file detected (penalty)")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No valid STL file found at expected path."
        }

    # Check 2: Geometry Content (10 pts)
    tri_count = result.get("triangle_count", 0)
    if tri_count > 10000:
        score += 10
        feedback_parts.append(f"Good geometry ({tri_count} triangles)")
    elif tri_count > 0:
        score += 5
        feedback_parts.append("Sparse geometry")
    else:
        feedback_parts.append("Empty mesh")

    # Check 3: Calibration / Dimensions (50 pts)
    # This is the critical skill check
    dims = result.get("dimensions", {})
    x_width = dims.get("x_width", 0.0)
    
    diff = abs(x_width - target_width)
    
    if diff <= tolerance:
        score += 50
        feedback_parts.append(f"Calibration CORRECT (Width: {x_width:.1f}mm)")
    else:
        # Check if they left it at default
        default_diff = abs(x_width - 512.0)
        if default_diff <= tolerance:
            feedback_parts.append(f"Calibration FAILED: Used default 1.0 spacing (Width: {x_width:.1f}mm)")
        else:
            feedback_parts.append(f"Calibration FAILED: Incorrect dimensions (Width: {x_width:.1f}mm, Target: {target_width}mm)")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }