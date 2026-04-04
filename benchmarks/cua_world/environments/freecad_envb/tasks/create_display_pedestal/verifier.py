#!/usr/bin/env python3
"""
Verifier for create_display_pedestal task.
Evaluates the geometric properties of the created FreeCAD model.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_display_pedestal(traj, env_info, task_info):
    """
    Verify the pedestal creation task.
    
    Criteria:
    1. File creation (10 pts)
    2. Valid geometry/Single Solid (25 pts)
    3. Dimensions/Bounding Box (30 pts)
    4. Volume Accuracy (35 pts) - This implicitly verifies the hole and components.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume_mm3', 1507429)
    vol_tol_percent = metadata.get('volume_tolerance_percent', 8)
    expected_bbox = metadata.get('expected_bbox_mm', [200, 200, 177])
    bbox_tol = metadata.get('bbox_tolerance_mm', 5)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Creation (10 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created successfully.")
    elif result.get('output_exists'):
        score += 5
        feedback_parts.append("File exists but timestamp check failed.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Get analysis data
    analysis = result.get('analysis', {})
    if analysis.get('error'):
        return {"passed": False, "score": score, "feedback": f"Geometry analysis failed: {analysis['error']}"}

    # 2. Valid Geometry (25 pts)
    if analysis.get('valid_doc'):
        score += 10
        if analysis.get('is_single_solid'):
            score += 15
            feedback_parts.append("Valid single solid created.")
        else:
            feedback_parts.append("Geometry is not a single fused solid.")
    else:
        feedback_parts.append("Document is invalid or empty.")

    # 3. Bounding Box (30 pts)
    # Check dimensions
    bbox = analysis.get('bbox', [0, 0, 0])
    dims_ok = 0
    for i, (actual, expected) in enumerate(zip(bbox, expected_bbox)):
        if abs(actual - expected) <= bbox_tol:
            dims_ok += 1
    
    score += dims_ok * 10
    if dims_ok == 3:
        feedback_parts.append("Dimensions correct.")
    else:
        feedback_parts.append(f"Dimensions incorrect: {bbox}")

    # 4. Volume Accuracy (35 pts)
    # This is the strongest check for the hole and correct primitives
    actual_vol = analysis.get('volume', 0)
    vol_diff_percent = abs(actual_vol - expected_vol) / expected_vol * 100 if expected_vol else 100
    
    if vol_diff_percent <= vol_tol_percent:
        score += 35
        feedback_parts.append(f"Volume correct ({actual_vol:.0f} mm³).")
    elif vol_diff_percent <= vol_tol_percent * 2:
        score += 15
        feedback_parts.append(f"Volume slightly off ({actual_vol:.0f} mm³).")
    else:
        feedback_parts.append(f"Volume incorrect ({actual_vol:.0f} vs {expected_vol} mm³).")

    return {
        "passed": score >= 60 and dims_ok >= 2 and analysis.get('is_single_solid', False),
        "score": score,
        "feedback": " ".join(feedback_parts)
    }