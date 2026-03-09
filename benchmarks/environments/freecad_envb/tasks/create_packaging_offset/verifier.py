#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_create_packaging_offset(traj, env_info, task_info):
    """
    Verifies that the agent created a correct 3D offset solid in FreeCAD.
    
    Verification Signals:
    1. File Existence & Metadata (Programmatic)
    2. Geometry Validity & Volume (Programmatic - via in-container script)
    3. UI Workflow (VLM - trajectory check)
    """
    
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function unavailable"}

    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_exists = result_data.get("file_exists", False)
    is_new = result_data.get("is_new_file", False)
    geo_check = result_data.get("geometry_check", {})
    
    obj_found = geo_check.get("object_found", False)
    valid_geo = geo_check.get("valid_geometry", False)
    is_solid = geo_check.get("is_solid", False)
    vol_match = geo_check.get("volume_match", False)
    
    # 3. Calculate Score
    score = 0
    feedback = []

    # File Checks (15 pts)
    if file_exists:
        score += 5
        if is_new:
            score += 10
            feedback.append("File created successfully.")
        else:
            feedback.append("File exists but timestamp indicates it wasn't modified.")
    else:
        feedback.append("Output file not found.")

    # Geometry Checks (65 pts)
    if obj_found:
        score += 10
        if valid_geo:
            score += 10
            if is_solid:
                score += 20
                feedback.append("Geometry is a valid solid.")
            else:
                feedback.append("Geometry is not a solid (likely a hollow shell or mesh).")
            
            if vol_match:
                score += 25
                feedback.append("Volume matches expected 2mm offset exactly.")
            else:
                # If valid solid but wrong volume, partial credit
                feedback.append(f"Volume mismatch. Got {geo_check.get('volume', 0):.1f}, expected ~{geo_check.get('ground_truth_volume', 0):.1f}")
        else:
            feedback.append("Object exists but has invalid geometry.")
    else:
        feedback.append("Target object 'ClearanceBody' (or valid offset) not found in file.")

    # 4. VLM Verification (20 pts)
    # Check if UI was used correctly (backup verification)
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and query_vlm:
        prompt = """
        Review these screenshots of a FreeCAD workflow.
        1. Does the user open a file with a mechanical part (T8 bracket)?
        2. Do you see the "Part" workbench being active (icon looks like yellow lego block)?
        3. Is the "3D Offset" tool used? (Dialog title "Offset" or "Utility to offset...")?
        4. Does the final view show a larger, possibly encompassing shape?
        """
        response = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if response.get("success"):
            # Simple keyword matching on reasoning if parsed unavailable
            text = response.get("response", "").lower()
            if "yes" in text and "offset" in text:
                vlm_score = 20
                feedback.append("Visual verification confirmed offset tool usage.")
            else:
                vlm_score = 10 # Partial credit for just showing FreeCAD
    
    score += vlm_score

    # 5. Final Determination
    # Must have a valid solid with matching volume to pass
    passed = (is_solid and vol_match and score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result_data
    }