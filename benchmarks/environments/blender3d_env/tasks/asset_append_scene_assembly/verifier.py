#!/usr/bin/env python3
"""
Verifier for asset_append_scene_assembly@1.

Verifies:
1. Output .blend file exists and was created during task.
2. Output .png render exists.
3. Scene contains appended Table, Chair, Bookshelf.
4. Objects are positioned correctly (on floor, in room, not overlapping).
5. Room structure (floor) is preserved.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_asset_append_scene_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result JSON: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Check File Existence (20 pts)
    blend_exists = result.get("blend_exists", False)
    blend_fresh = result.get("blend_created_during", False)
    image_exists = result.get("image_exists", False)
    
    if blend_exists and blend_fresh:
        score += 10
        feedback.append("Blend file saved.")
    else:
        feedback.append("Blend file missing or not saved.")
        
    if image_exists:
        score += 10
        feedback.append("Rendered image saved.")
    else:
        feedback.append("Rendered image missing.")

    # 3. Analyze Scene Content (80 pts)
    analysis = result.get("scene_analysis", {})
    found_objects = analysis.get("found_objects", {})
    
    required = ["Table", "Chair", "Bookshelf"]
    
    # Check object presence (30 pts - 10 per object)
    present_count = 0
    for req in required:
        if req in found_objects:
            score += 10
            present_count += 1
        else:
            feedback.append(f"Missing object: {req}")
    
    if present_count == 3:
        feedback.append("All required objects appended.")

    # Check positioning (30 pts)
    # Only check positioning if objects exist
    position_score = 0
    for req in required:
        if req in found_objects:
            obj_data = found_objects[req]
            
            # Check floor placement
            if obj_data.get("on_floor", False):
                position_score += 5
            else:
                feedback.append(f"{req} is not on the floor (floating/sunk).")
            
            # Check room bounds
            if obj_data.get("in_room", False):
                position_score += 5
            else:
                feedback.append(f"{req} is outside room walls.")
    
    score += position_score

    # Check overlaps (10 pts)
    overlaps = analysis.get("overlaps", [])
    if not overlaps and present_count > 1:
        score += 10
        feedback.append("No object overlaps detected.")
    elif overlaps:
        feedback.append(f"Objects overlapping: {', '.join(overlaps)}")

    # Check room integrity (10 pts)
    if analysis.get("room_integrity", False):
        score += 10
    else:
        feedback.append("Room floor missing (scene corrupted).")

    # Final result
    passed = (score >= 60 and present_count == 3 and blend_exists)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }