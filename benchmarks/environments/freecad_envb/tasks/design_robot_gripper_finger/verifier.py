#!/usr/bin/env python3
"""
Verifier for design_robot_gripper_finger task.
Uses multi-factor authentication:
1. File existence and creation time.
2. Programmatic geometry analysis (performed inside env, read via JSON).
3. VLM verification of the workflow/final state.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_robot_gripper_finger(traj, env_info, task_info):
    """
    Verify the custom gripper finger design.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    geo = result.get("geometry_analysis", {})
    
    score = 0
    feedback_parts = []
    
    # 3. Basic File Checks (20 pts)
    if file_exists:
        score += 10
        feedback_parts.append("File exists")
        if created_during:
            score += 10
            feedback_parts.append("Created during task")
        else:
            feedback_parts.append("File timestamp too old")
    else:
        feedback_parts.append("File not found")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # 4. Geometric Analysis (60 pts)
    if geo.get("valid_solid"):
        score += 10 # Solid exists
        
        # Bounding Box (20 pts)
        bbox = geo.get("bbox", [0, 0, 0])
        # Expected: 100 x 30 x 15
        if abs(bbox[0] - 100) < 2 and abs(bbox[1] - 30) < 2 and abs(bbox[2] - 15) < 2:
            score += 20
            feedback_parts.append("Dimensions correct")
        else:
            feedback_parts.append(f"Dimensions incorrect ({bbox[0]:.1f}x{bbox[1]:.1f}x{bbox[2]:.1f})")

        # Volume (10 pts)
        vol = geo.get("volume", 0)
        # Expected ~43500
        if abs(vol - 43500) < 3000:
            score += 10
            feedback_parts.append("Volume correct")
        
        # Features (20 pts)
        if geo.get("holes_detected"):
            score += 10
            feedback_parts.append("Holes detected")
        else:
            feedback_parts.append("Holes missing/incorrect")
            
        if geo.get("groove_detected"):
            score += 10
            feedback_parts.append("V-groove detected")
        else:
            feedback_parts.append("Groove missing/incorrect")
    else:
        feedback_parts.append("No valid solid found in file")

    # 5. VLM Verification (20 pts)
    # Check if the agent was actually doing CAD work
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not frames:
        feedback_parts.append("No trajectory frames")
    else:
        # Prompt for VLM
        prompt = """
        Review these screenshots of a user working in FreeCAD.
        Task: Design a rectangular robot gripper finger with holes and a V-groove.
        
        Check for:
        1. Is FreeCAD visible?
        2. Is there a 3D model being edited?
        3. Does the final shape look like a rectangular block with holes?
        4. Do you see any dialogs related to Sketcher, Part Design, or Primitives?
        
        Return JSON: {"cad_work_visible": bool, "shape_match": bool}
        """
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("cad_work_visible"):
                score += 10
                feedback_parts.append("VLM: CAD work confirmed")
            if parsed.get("shape_match"):
                score += 10
                feedback_parts.append("VLM: Shape looks correct")
        else:
            # Fallback if VLM fails but program check passed
            if score >= 60:
                score += 10
                feedback_parts.append("VLM skipped (program pass)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }