#!/usr/bin/env python3
"""
Verifier for freestyle_line_art_render task.

Criteria:
1. Freestyle enabled in scene (20 pts)
2. Line thickness 2.0-5.0px (15 pts)
3. Line color black (10 pts)
4. World background white (15 pts)
5. Render output valid (size, res, timestamp) (25 pts)
6. Blend file saved (15 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_freestyle_line_art(traj, env_info, task_info):
    """
    Verify the Freestyle line art task based on exported JSON data and VLM check.
    """
    # 1. Setup - Get Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    scene_data = result.get("scene_data", {})
    metadata = task_info.get("metadata", {})
    
    # 3. Score Calculation
    score = 0
    feedback = []
    
    # -- Criterion 1: Blend File Saved (15 pts) --
    if result.get("blend_exists") and result.get("blend_valid"):
        score += 15
        feedback.append("✅ Project saved.")
    else:
        feedback.append("❌ Project file not saved or invalid.")

    # -- Criterion 2: Freestyle Enabled (20 pts) --
    if scene_data.get("use_freestyle", False):
        score += 20
        feedback.append("✅ Freestyle enabled.")
    else:
        feedback.append("❌ Freestyle NOT enabled in render settings.")

    # -- Criterion 3: Line Configuration (25 pts total) --
    line_sets = scene_data.get("line_sets", [])
    if not line_sets and scene_data.get("use_freestyle", False):
         feedback.append("⚠️ Freestyle on, but no line sets found.")
    
    valid_thickness = False
    valid_color = False
    
    for ls in line_sets:
        # Check Thickness (15 pts)
        thickness = ls.get("thickness", 0)
        min_th = metadata.get("min_line_thickness", 2.0)
        max_th = metadata.get("max_line_thickness", 5.0)
        
        if min_th <= thickness <= max_th:
            valid_thickness = True
            
        # Check Color (10 pts)
        color = ls.get("color", [1, 1, 1])
        # Check if color is near black (all channels < threshold)
        threshold = metadata.get("max_line_color_val", 0.15)
        if all(c <= threshold for c in color[:3]):
            valid_color = True
            
    if valid_thickness:
        score += 15
        feedback.append("✅ Line thickness within target range.")
    else:
        feedback.append("❌ Line thickness incorrect (target: 2.0-5.0px).")
        
    if valid_color:
        score += 10
        feedback.append("✅ Line color is black.")
    else:
        feedback.append("❌ Line color is not black.")

    # -- Criterion 4: World Background White (15 pts) --
    world_color = scene_data.get("world_color", [0, 0, 0])
    bg_threshold = metadata.get("min_bg_color_val", 0.85)
    
    # Check if all channels are bright
    if all(c >= bg_threshold for c in world_color):
        score += 15
        feedback.append("✅ World background is white.")
    else:
        feedback.append("❌ World background is not white.")

    # -- Criterion 5: Render Output (25 pts) --
    render_exists = result.get("render_exists")
    render_fresh = result.get("render_created_during_task")
    render_size = result.get("render_size_bytes", 0)
    render_w = result.get("render_width", 0)
    render_h = result.get("render_height", 0)
    
    if render_exists and render_fresh and render_size > 50000: # 50KB min
        # Check resolution
        exp_res = metadata.get("expected_resolution", [1920, 1080])
        if abs(render_w - exp_res[0]) < 10 and abs(render_h - exp_res[1]) < 10:
            score += 25
            feedback.append("✅ Render output valid and high resolution.")
        else:
            score += 15 # Partial credit for render exists but wrong res
            feedback.append(f"⚠️ Render exists but wrong resolution ({render_w}x{render_h}).")
    elif render_exists and not render_fresh:
         feedback.append("❌ Render file exists but timestamp indicates it wasn't created during this task.")
    else:
         feedback.append("❌ No valid render output found.")

    # 4. Optional VLM Verification (Bonus/Confirmation)
    # If we have VLM access, verify the visual style
    query_vlm = env_info.get('query_vlm')
    if query_vlm and result.get("render_exists"):
        # We can try to get the render file from container or use the final screenshot from trajectory
        # Since we can't easily pull the render file to host in this flow without complex copying,
        # we'll use the final screenshot provided in the trajectory if available.
        # Ideally, we would inspect the generated PNG, but verifying the screen state is a good proxy.
        
        from gym_anything.vlm import get_final_screenshot
        final_screen = get_final_screenshot(traj)
        
        if final_screen:
            prompt = """
            Look at this Blender screenshot. 
            1. Is the background pure white or near white?
            2. Do you see a 3D car model rendered as 'line art' or 'technical drawing' (black outlines)?
            3. Is it distinct from a standard photorealistic render (no heavy shading/textures)?
            Return JSON: {"is_line_art": bool, "white_background": bool}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=final_screen)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("is_line_art") and parsed.get("white_background"):
                        feedback.append("✅ VLM confirms line art visual style.")
                    else:
                        feedback.append("⚠️ VLM could not confirm visual style (might be obscured).")
            except Exception:
                pass

    # 5. Final Result
    passed = score >= 70 and scene_data.get("use_freestyle", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }