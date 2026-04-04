#!/usr/bin/env python3
"""
Verifier for constrain_mechanical_profile task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_constrain_mechanical_profile(traj, env_info, task_info):
    """
    Verifies that the agent fully constrained the FreeCAD sketch.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result data from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Result Data
    file_exists = result.get("file_exists", False)
    file_modified = result.get("file_modified", False)
    analysis = result.get("analysis", {})
    
    has_length = analysis.get("has_length_constraint", False)
    has_radius = analysis.get("has_radius_constraint", False)
    is_fully_constrained = analysis.get("is_fully_constrained", False)
    
    # 3. Scoring
    score = 0
    feedback_parts = []
    
    # Criterion: File saved (10 pts)
    if file_exists and file_modified:
        score += 10
        feedback_parts.append("File saved successfully.")
    elif file_exists:
        feedback_parts.append("File exists but was not modified (saved).")
    else:
        feedback_parts.append("File not found.")
        return {"passed": False, "score": 0, "feedback": "File not found."}

    # Criterion: Valid Doc & Sketch (10 pts)
    if analysis.get("valid_doc") and analysis.get("has_sketch"):
        score += 10
    else:
        feedback_parts.append("Document or Sketch corrupted.")

    # Criterion: Length Constraint Correct (25 pts)
    if has_length:
        score += 25
        feedback_parts.append("Length constraint (120mm) applied.")
    else:
        feedback_parts.append("Missing or incorrect length constraint.")

    # Criterion: Radius Constraint Correct (25 pts)
    if has_radius:
        score += 25
        feedback_parts.append("Radius constraint (25mm) applied.")
    else:
        feedback_parts.append("Missing or incorrect radius constraint.")

    # Criterion: Fully Constrained Geometry (30 pts)
    # This is determined by the bounding box check in the internal script
    if is_fully_constrained:
        score += 30
        feedback_parts.append("Sketch is fully constrained (geometry matches expected).")
    else:
        feedback_parts.append("Sketch geometry does not match expected fully constrained dimensions.")

    # 4. VLM Verification (Bonus/Confirmation)
    # We check if the sketch color turned green (FreeCAD standard for fully constrained)
    frames = sample_trajectory_frames(traj, n=2)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = """
        Does the sketch in the FreeCAD viewport appear green? 
        In FreeCAD, bright green lines usually indicate a fully constrained sketch. 
        White lines indicate under-constrained geometry.
        """
        try:
            vlm_res = query_vlm(images=[final_screen], prompt=vlm_prompt)
            if vlm_res.get("success") and "green" in str(vlm_res.get("parsed", "")).lower():
                # This confirms the programmatic check
                pass 
        except:
            pass

    passed = score >= 90  # High bar because precision is required
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }