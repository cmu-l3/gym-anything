#!/usr/bin/env python3
"""
Verifier for pbr_material_assembly task.

SCORING CRITERIA:
1. Base Color Setup (15 pts): Diffuse texture connected to Base Color.
2. Roughness Setup (25 pts): Roughness texture connected AND Color Space is Non-Color.
3. Normal Map Setup (25 pts): Normal texture -> Normal Map Node -> Normal input AND Color Space is Non-Color.
4. Mapping Setup (15 pts): Texture Coordinate and Mapping nodes present (programmatic check implies intent).
5. Output Files (20 pts): Render exists and Blend file saved.

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pbr_material_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
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
    
    analysis = result.get("analysis", {})
    if not analysis:
        return {"passed": False, "score": 0, "feedback": "Could not analyze Blender file (file may not exist or is corrupt)."}

    textures = analysis.get("textures", {})
    nodes = analysis.get("nodes", [])
    
    # 1. Base Color Setup (15 pts)
    diffuse = textures.get("diffuse")
    if diffuse:
        img_name = diffuse.get("image", "").lower()
        if "diffuse" in img_name or "diff" in img_name:
            score += 15
            feedback.append("✅ Diffuse texture connected correctly.")
        else:
            score += 10 # Connected something, but maybe wrong image
            feedback.append("⚠️ Base Color connected, but image name doesn't contain 'diffuse'.")
    else:
        feedback.append("❌ Base Color not connected to an Image Texture.")

    # 2. Roughness Setup (25 pts)
    roughness = textures.get("roughness")
    if roughness:
        img_name = roughness.get("image", "").lower()
        cs = roughness.get("colorspace", "sRGB")
        
        points = 0
        if "roughness" in img_name or "rough" in img_name:
            points += 10
        
        # Check for Non-Color data (Blender calls it 'Non-Color')
        if cs in ["Non-Color", "Raw", "Non-Color Data"]:
            points += 15
            feedback.append("✅ Roughness Color Space set to Non-Color.")
        else:
            feedback.append(f"❌ Roughness Color Space is '{cs}' (Expected: Non-Color).")
            
        score += points
        if points > 0:
            feedback.append("✅ Roughness texture connected.")
    else:
        feedback.append("❌ Roughness input not connected.")

    # 3. Normal Map Setup (25 pts)
    normal = textures.get("normal")
    if normal:
        img_name = normal.get("image", "").lower()
        cs = normal.get("colorspace", "sRGB")
        via_node = normal.get("via_normal_map_node", False)
        
        points = 0
        if "normal" in img_name or "nor" in img_name:
            points += 5
            
        if via_node:
            points += 10
            feedback.append("✅ Normal Map node used.")
        else:
            feedback.append("❌ Normal texture connected directly (missing Normal Map node).")
            
        if cs in ["Non-Color", "Raw", "Non-Color Data"]:
            points += 10
            feedback.append("✅ Normal Color Space set to Non-Color.")
        else:
            feedback.append(f"❌ Normal Color Space is '{cs}' (Expected: Non-Color).")
            
        score += points
    else:
        feedback.append("❌ Normal input not connected properly.")

    # 4. Mapping Setup (15 pts)
    # Check if Texture Coordinate and Mapping nodes exist in the graph
    has_mapping = any(n['type'] == 'MAPPING' for n in nodes)
    has_coord = any(n['type'] == 'TEX_COORD' for n in nodes)
    
    if has_mapping and has_coord:
        score += 15
        feedback.append("✅ Mapping and Texture Coordinate nodes detected.")
    elif has_mapping or has_coord:
        score += 5
        feedback.append("⚠️ Partial mapping setup found.")
    else:
        feedback.append("❌ No Mapping/Coordinate nodes found.")

    # 5. Output Files (20 pts)
    if result.get("render_exists") and result.get("render_size", 0) > 50000:
        score += 10
        feedback.append("✅ Render output found.")
    else:
        feedback.append("❌ Valid render output not found.")
        
    if result.get("blend_exists"):
        score += 10
        feedback.append("✅ Project file saved.")
    else:
        feedback.append("❌ Project file not saved.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }