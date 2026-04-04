#!/usr/bin/env python3
"""
Verifier for texture_paint_wear_mask task.

Criteria:
1. wear_mask.png exists and has painted content (not blank/solid).
2. Blend file contains UVs for the object.
3. Material node graph correctly uses the mask to mix shaders.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_texture_paint_wear_mask(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []
    
    # 1. Image Saved (20 pts)
    img_data = result.get("image_analysis", {})
    if result.get("image_path_exists", False) and img_data.get("exists", False):
        score += 20
        feedback.append("Image file saved.")
        
        # 2. Painting Detected (25 pts)
        has_content = img_data.get("has_content", False)
        is_solid = img_data.get("is_solid_fill", False)
        
        if has_content and not is_solid:
            score += 25
            feedback.append("Painted content detected on mask.")
        elif is_solid:
            feedback.append("Image appears to be a solid fill, not painted details.")
        else:
            feedback.append("Image is empty (black).")
    else:
        feedback.append("wear_mask.png not found.")

    # 3. Blend File & UVs (30 pts)
    scene_data = result.get("scene_analysis", {})
    if result.get("blend_path_exists", False):
        score += 15
        feedback.append("Blend file saved.")
        
        if scene_data.get("uvs_exist", False):
            score += 15
            feedback.append("Object UVs created.")
        else:
            feedback.append("Object has no UV map (Smart UV Project needed).")
    else:
        feedback.append("distressed_crate.blend not found.")

    # 4. Material Setup (25 pts)
    if scene_data.get("image_node_found", False):
        if scene_data.get("mix_node_found", False):
            if scene_data.get("links_correct", False):
                score += 25
                feedback.append("Material nodes correctly set up (Mask -> Mix Factor).")
            else:
                score += 10
                feedback.append("Nodes found but mask is not linked to Mix Factor.")
        else:
            score += 5
            feedback.append("Image Texture node found, but Mix Shader missing.")
    else:
        feedback.append("No Image Texture node referencing 'wear_mask' found in material.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }