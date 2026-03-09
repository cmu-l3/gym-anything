#!/usr/bin/env python3
"""
Verifier for create_compression_spring task.

Scoring Criteria:
1. File Creation (10 pts): Valid FCStd file created during task.
2. Solid Geometry (20 pts): File contains a 3D solid.
3. Dimensions (35 pts): Bounding box matches specifications (Height ~42mm, Width ~20mm).
4. Volume (20 pts): Volume matches theoretical helix sweep (~1427 mm³).
5. VLM Verification (15 pts): Trajectory shows Helix primitive and Sweep usage.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_compression_spring(traj, env_info, task_info):
    """
    Verify the agent created a correct compression spring.
    """
    # 0. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    EXP_VOL = metadata.get('expected_volume_mm3', 1426.7)
    VOL_TOL = metadata.get('volume_tolerance_percent', 25) / 100.0
    
    EXP_BB_X = metadata.get('expected_bbox_x', 20.0)
    EXP_BB_Z = metadata.get('expected_bbox_z', 42.0)
    BB_TOL = metadata.get('bbox_tolerance_mm', 3.0)

    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON from Container
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

    # 2. Verify File Basics (10 pts)
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file compression_spring.FCStd not found."}
    
    if not result.get('file_modified_in_task'):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

    score += 10
    feedback_parts.append("File created successfully.")

    # 3. Verify Geometry Existence (20 pts)
    geom = result.get('geometry', {})
    if not geom.get('has_solid'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "File contains no valid 3D solid geometry."
        }
    
    score += 20
    feedback_parts.append("Solid geometry found.")

    # 4. Verify Dimensions (35 pts)
    bbox = geom.get('bbox', [0, 0, 0]) # [X, Y, Z]
    actual_x, actual_y, actual_z = bbox[0], bbox[1], bbox[2]
    
    # Check X/Y (Diameter ~ 20mm)
    # We check max(X,Y) to be robust against orientation, though Z is usually height
    xy_avg = (actual_x + actual_y) / 2
    
    # Check Height (Z ~ 42mm)
    # The helix is 40mm high (8 * 5), plus wire thickness (2mm) = ~42mm
    
    dims_ok = True
    if abs(actual_z - EXP_BB_Z) > BB_TOL:
        feedback_parts.append(f"Height incorrect: {actual_z:.1f}mm (expected {EXP_BB_Z}mm)")
        dims_ok = False
    else:
        score += 15
        
    if abs(xy_avg - EXP_BB_X) > BB_TOL:
        feedback_parts.append(f"Diameter incorrect: {xy_avg:.1f}mm (expected {EXP_BB_X}mm)")
        dims_ok = False
    else:
        score += 20
        
    if dims_ok:
        feedback_parts.append("Dimensions correct.")

    # 5. Verify Volume (20 pts)
    # Theoretical: Length ~ 454mm * Area (pi*1^2) ~ 1426 mm^3
    vol = geom.get('volume', 0)
    min_vol = EXP_VOL * (1 - VOL_TOL)
    max_vol = EXP_VOL * (1 + VOL_TOL)
    
    if min_vol <= vol <= max_vol:
        score += 20
        feedback_parts.append(f"Volume correct ({vol:.1f} mm³).")
    else:
        feedback_parts.append(f"Volume mismatch: {vol:.1f} mm³ (expected {min_vol:.0f}-{max_vol:.0f}).")

    # 6. VLM Verification (15 pts)
    # Check trajectory for Helix creation and Sweep
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user working in FreeCAD.
        Check for the following:
        1. Creation of a **Helix** primitive (spiral line).
        2. Creation of a **Circle** sketch.
        3. Use of the **Sweep** (or Pipe) tool to create a spring shape.
        4. Final result looks like a coiled spring.
        
        Return JSON: {"helix_seen": bool, "sweep_seen": bool, "spring_shape_visible": bool}
        """
        
        vlm_res = query_vlm(prompt, images=frames)
        vlm_data = vlm_res.get('parsed', {})
        
        if vlm_data.get('spring_shape_visible') or (vlm_data.get('helix_seen') and vlm_data.get('sweep_seen')):
            score += 15
            feedback_parts.append("Visual verification passed.")
        else:
            feedback_parts.append("Visual verification inconclusive.")
    else:
        # Fallback if no frames available but geometry is perfect
        if score >= 70:
            score += 15
            feedback_parts.append("Visual check skipped (geometry good).")

    # Final Pass Determination
    # Must have decent dimensions and volume
    passed = (score >= 70) and geom.get('has_solid')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }