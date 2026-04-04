#!/usr/bin/env python3
"""
Verifier for radial_array_modifier_setup task.

Verification Criteria:
1. Empty object exists at origin (0,0,0) - 15 pts
2. Empty has Z-rotation approx 60 degrees - 15 pts
3. Array modifier exists on a mesh - 15 pts
4. Array count is 6 - 15 pts
5. Array uses Object Offset pointing to an Empty - 15 pts
6. Blade mesh is elongated (aspect ratio > 2.0) - 10 pts
7. File saved and valid - 15 pts
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_radial_array(traj, env_info, task_info):
    """
    Verify the 6-blade radial array setup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    file_info = result.get("file", {})
    scene = result.get("scene", {})
    
    score = 0
    feedback_parts = []
    
    # 1. Check if file was saved
    if file_info.get("exists") and file_info.get("valid_blend"):
        score += 15
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("File not saved/invalid")
        # Fail early if no file
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No output file found", 
            "details": {"file_saved": False}
        }
    
    # 2. Check for Empty at origin
    empties = scene.get("empties", [])
    empty_at_origin = False
    target_empty_name = None
    
    for emp in empties:
        loc = emp.get("location", [10, 10, 10])
        dist = math.sqrt(sum(x**2 for x in loc))
        if dist < 0.5:
            empty_at_origin = True
            target_empty_name = emp.get("name")
            break
            
    if empty_at_origin:
        score += 15
        feedback_parts.append("Empty at origin found")
    else:
        feedback_parts.append("No Empty object at origin")

    # 3. Check Empty rotation (60 degrees)
    rotation_ok = False
    if target_empty_name:
        for emp in empties:
            if emp.get("name") == target_empty_name:
                rot_deg = emp.get("rotation_euler_deg", [0, 0, 0])
                z_rot = abs(rot_deg[2]) % 360
                # Check 60 or 300 (-60)
                if abs(z_rot - 60) < 5 or abs(z_rot - 300) < 5:
                    rotation_ok = True
                break
    
    if rotation_ok:
        score += 15
        feedback_parts.append("Empty rotation ~60°")
    else:
        feedback_parts.append("Empty rotation incorrect (expected 60°)")

    # 4. Check Array Modifier
    array_mods = scene.get("array_modifiers", [])
    has_array = len(array_mods) > 0
    
    if has_array:
        score += 15
        feedback_parts.append("Array modifier found")
    else:
        feedback_parts.append("No Array modifier found")

    # 5. Check Array Count
    count_ok = False
    target_array_mod = None
    
    for mod in array_mods:
        if mod.get("count") == 6:
            count_ok = True
            target_array_mod = mod
            break
    
    if count_ok:
        score += 15
        feedback_parts.append("Array count 6")
    else:
        feedback_parts.append("Array count incorrect")

    # 6. Check Object Offset
    offset_ok = False
    if target_array_mod:
        if (target_array_mod.get("use_object_offset") and 
            target_array_mod.get("offset_object_type") == "EMPTY"):
            offset_ok = True
            
    if offset_ok:
        score += 15
        feedback_parts.append("Object Offset correct")
    else:
        feedback_parts.append("Object Offset missing/incorrect")

    # 7. Check Blade Shape (Elongated)
    blade_ok = False
    if target_array_mod:
        obj_name = target_array_mod.get("object_name")
        bbox_data = scene.get("mesh_bounding_boxes", {}).get(obj_name, {})
        ar = bbox_data.get("aspect_ratio", 0)
        if ar >= 2.0:
            blade_ok = True
            
    if blade_ok:
        score += 10
        feedback_parts.append("Blade shape elongated")
    else:
        feedback_parts.append("Blade shape too square/cube-like")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "empty_at_origin": empty_at_origin,
            "rotation_ok": rotation_ok,
            "has_array": has_array,
            "count_ok": count_ok,
            "offset_ok": offset_ok,
            "blade_ok": blade_ok
        }
    }