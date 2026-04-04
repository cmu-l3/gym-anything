#!/usr/bin/env python3
"""
Verifier for curate_anatomical_masks task.

Criteria:
1. File exists and is valid (10 pts)
2. Exactly 3 masks exist (15 pts)
3. Naming convention correct (Standard_Bone, Standard_Skin, Standard_Air) (25 pts)
4. Color coding correct (White, Pink/Red, Blue/Cyan) (25 pts)
5. Threshold logic correct for tissue types (25 pts)

Pass threshold: 75 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_curate_anatomical_masks(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read export result: {e}"
        }

    score = 0
    feedback_parts = []
    
    # 1. File Validity & Existence (10 pts)
    if result.get("file_exists") and result.get("file_valid"):
        score += 10
        feedback_parts.append("Project file saved validly")
    elif result.get("file_exists"):
        feedback_parts.append("File exists but is corrupted/invalid")
        return {"passed": False, "score": 0, "feedback": "File corrupted"}
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": 0, "feedback": "File not found"}

    # 2. Mask Count (15 pts)
    mask_count = result.get("mask_count", 0)
    if mask_count == 3:
        score += 15
        feedback_parts.append("Correct number of masks (3)")
    else:
        feedback_parts.append(f"Incorrect mask count: {mask_count} (expected 3)")

    # Analyze Masks
    masks = result.get("masks", [])
    
    # Find specific masks by name (case-insensitive)
    bone_mask = next((m for m in masks if "standard_bone" in m["name"].lower()), None)
    skin_mask = next((m for m in masks if "standard_skin" in m["name"].lower()), None)
    air_mask = next((m for m in masks if "standard_air" in m["name"].lower()), None)
    
    # 3. Naming Convention (25 pts total)
    naming_score = 0
    if bone_mask: naming_score += 8
    if skin_mask: naming_score += 8
    if air_mask: naming_score += 9
    
    score += naming_score
    if naming_score == 25:
        feedback_parts.append("All masks named correctly")
    else:
        feedback_parts.append(f"Naming score: {naming_score}/25")

    # 4. Color Coding (25 pts total)
    # Colors in InVesalius are RGB tuples [0.0-1.0]
    color_score = 0
    
    def is_white_ish(rgb):
        return all(c > 0.8 for c in rgb)
        
    def is_red_pink_ish(rgb):
        # R dominant
        r, g, b = rgb
        return r > 0.5 and r > g and r > b
        
    def is_blue_cyan_ish(rgb):
        # B or G dominant
        r, g, b = rgb
        return (b > r and b > 0.5) or (g > r and g > 0.5)

    if bone_mask and is_white_ish(bone_mask["color"]):
        color_score += 8
    elif bone_mask:
        feedback_parts.append(f"Bone color incorrect: {bone_mask['color']}")

    if skin_mask and is_red_pink_ish(skin_mask["color"]):
        color_score += 8
    elif skin_mask:
        feedback_parts.append(f"Skin color incorrect: {skin_mask['color']}")

    if air_mask and is_blue_cyan_ish(air_mask["color"]):
        color_score += 9
    elif air_mask:
        feedback_parts.append(f"Air color incorrect: {air_mask['color']}")
        
    score += color_score

    # 5. Threshold Logic (25 pts total)
    thresh_score = 0
    
    if bone_mask:
        min_hu = bone_mask["threshold_range"][0]
        if min_hu > 100: # Bone usually starts > 200
            thresh_score += 8
        else:
            feedback_parts.append(f"Bone threshold too low ({min_hu})")
            
    if air_mask:
        max_hu = air_mask["threshold_range"][1]
        if max_hu < -200: # Air usually ends < -700, but allow generous buffer
            thresh_score += 9
        else:
            feedback_parts.append(f"Air threshold too high ({max_hu})")
            
    if skin_mask:
        min_hu, max_hu = skin_mask["threshold_range"]
        # Skin/Soft tissue usually -700 to 200
        if min_hu < 0 and max_hu < 600:
            thresh_score += 8
        else:
            feedback_parts.append(f"Skin threshold out of range ({min_hu}-{max_hu})")

    score += thresh_score

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }