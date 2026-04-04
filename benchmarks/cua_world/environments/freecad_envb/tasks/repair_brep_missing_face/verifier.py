#!/usr/bin/env python3
"""
Verifier for repair_brep_missing_face task.

Verification Logic:
1. File Existence & Timestamps (Anti-gaming)
2. Geometric Validity (from analysis JSON generated inside env):
   - Must be a 'Solid'
   - Must be 'Closed' (Watertight)
   - Volume must match Ground Truth (±Tolerance)
   - Center of Mass must match Ground Truth (±Tolerance)
3. VLM Verification (Trajectory):
   - Confirm agent used Part workbench tools (Make face, Union, etc.)
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_repair_brep_missing_face(traj, env_info, task_info):
    """
    Verifies that the broken B-Rep geometry was repaired into a solid.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # Retrieve metadata requirements
    metadata = task_info.get('metadata', {})
    gt_volume = metadata.get('ground_truth_volume', 44615.0)
    vol_tol = metadata.get('volume_tolerance', 500.0)
    gt_com = metadata.get('ground_truth_com', [-1.08, 23.4, 15.0])
    com_tol = metadata.get('com_tolerance', 2.0)

    # 2. Retrieve Result JSON from Container
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

    # 3. Parse Programmatic Metrics
    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    geo = result.get('geometry_analysis', {})
    
    # CRITERION 1: File Existence & Anti-Gaming (15 pts)
    if output_exists and created_during_task:
        score += 15
        feedback_parts.append("File created successfully")
    elif output_exists:
        score += 5
        feedback_parts.append("File exists but timestamp is suspicious")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # CRITERION 2: Object Type (ShapeType) (25 pts)
    # Must be 'Solid'. 'Shell' means they didn't finish converting.
    shape_type = geo.get('shape_type', 'None')
    if shape_type == 'Solid':
        score += 25
        feedback_parts.append("Geometry converted to Solid")
    elif shape_type == 'Shell':
        score += 10
        feedback_parts.append("Geometry is still a Shell (not Solid)")
    else:
        feedback_parts.append(f"Invalid geometry type: {shape_type}")

    # CRITERION 3: Watertightness (isClosed) (20 pts)
    is_closed = geo.get('is_closed', False)
    if is_closed:
        score += 20
        feedback_parts.append("Solid is watertight (Closed)")
    else:
        feedback_parts.append("Geometry is not watertight (Open)")

    # CRITERION 4: Geometric Accuracy (Volume & CoM) (20 pts)
    # Volume Check
    vol = geo.get('volume', 0.0)
    vol_diff = abs(vol - gt_volume)
    
    # CoM Check (Manhattan distance for simplicity)
    com_x = geo.get('com_x', 0)
    com_y = geo.get('com_y', 0)
    com_z = geo.get('com_z', 0)
    com_diff = (abs(com_x - gt_com[0]) + abs(com_y - gt_com[1]) + abs(com_z - gt_com[2]))
    
    accuracy_passed = False
    if vol_diff <= vol_tol and com_diff <= com_tol:
        score += 20
        accuracy_passed = True
        feedback_parts.append(f"Geometry accurate (Vol error: {vol_diff:.1f}mm³)")
    elif vol_diff <= vol_tol:
        score += 10
        feedback_parts.append(f"Volume correct but position wrong (CoM error: {com_diff:.1f}mm)")
    else:
        feedback_parts.append(f"Geometry mismatch (Vol error: {vol_diff:.1f}mm³)")

    # 4. VLM Verification (20 pts)
    # Check if they actually performed the repair steps
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a CAD repair task in FreeCAD.
    The user needs to:
    1. Select edges of a hole.
    2. Create a face (e.g. 'Make face from wires').
    3. Union/Sew the face with the shell.
    4. Convert to Solid.

    Look at the image sequence. Do you see evidence of:
    - A missing face (hole) in the model initially?
    - Selection of edges around the hole?
    - The hole being filled (color/surface appearing)?
    - Use of Part Workbench tools?

    Answer yes/no and provide brief reasoning.
    """
    
    vlm_score = 0
    try:
        # We assume query_vlm handles the list of images
        vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            # Simple heuristic based on generic positive response or keywords in reasoning
            # Adjust based on actual VLM output structure
            reasoning = vlm_res.get('response', '').lower()
            if "yes" in reasoning or "filled" in reasoning or "repaired" in reasoning:
                vlm_score = 20
                feedback_parts.append("VLM confirmed repair workflow")
            else:
                feedback_parts.append("VLM could not confirm repair workflow")
        else:
            # Fallback if VLM fails: give points if geometry is perfect (benefit of doubt)
            if accuracy_passed and is_closed:
                vlm_score = 20
                feedback_parts.append("VLM skipped (Geometry perfect)")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful degradation
        if accuracy_passed:
            vlm_score = 20

    score += vlm_score

    # 5. Final Pass Determination
    # Must have a Solid, Closed, and reasonable geometry
    key_requirements = (shape_type == 'Solid') and is_closed and accuracy_passed
    passed = (score >= 70) and key_requirements

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "volume_measured": vol,
            "volume_expected": gt_volume,
            "is_solid": (shape_type == 'Solid'),
            "is_closed": is_closed
        }
    }