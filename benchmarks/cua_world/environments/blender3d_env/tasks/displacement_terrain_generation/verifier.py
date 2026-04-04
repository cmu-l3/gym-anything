#!/usr/bin/env python3
"""
Verifier for displacement_terrain_generation task.
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_terrain_generation(traj, env_info, task_info):
    """
    Verifies the terrain generation task based on:
    1. Scene Analysis (from .blend file):
       - Vertex count (high subdivision)
       - Displace modifier presence & settings
       - Procedural texture usage
       - Material properties (color, roughness)
       - Camera position
    2. Render Output:
       - File existence and size
    3. VLM Verification (Bonus/Confirmation):
       - Visual check for mountainous terrain
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    scene_data = result.get("scene_analysis", {})
    render_exists = result.get("render_exists", False)
    render_fresh = result.get("render_created_during_task", False)
    
    score = 0
    feedback = []
    
    # --- Criterion 1: Mesh Resolution (15 pts) ---
    # Need high vertex count for displacement to work well
    max_verts = scene_data.get("max_vertices", 0)
    min_verts = metadata.get("min_vertex_count", 10000)
    
    if max_verts >= min_verts:
        score += 15
        feedback.append(f"✅ Mesh subdivision sufficient ({max_verts} vertices)")
    elif max_verts > 1000:
        score += 5
        feedback.append(f"⚠️ Mesh partially subdivided ({max_verts} vertices), needs more for quality displacement")
    else:
        feedback.append(f"❌ Mesh vertex count too low ({max_verts}) for terrain")

    # --- Criterion 2: Displace Modifier (15 pts) ---
    has_displace = scene_data.get("has_displace", False)
    strength = abs(scene_data.get("displace_strength", 0.0))
    min_str = metadata.get("min_displace_strength", 1.0)
    
    if has_displace:
        if strength >= min_str:
            score += 15
            feedback.append(f"✅ Displace modifier configured (strength {strength:.2f})")
        elif strength > 0.1:
            score += 10
            feedback.append(f"⚠️ Displace modifier present but strength low ({strength:.2f})")
        else:
            score += 5
            feedback.append("❌ Displace modifier has zero strength")
    else:
        feedback.append("❌ No Displace modifier found on terrain mesh")

    # --- Criterion 3: Procedural Texture (15 pts) ---
    has_proc_tex = scene_data.get("has_procedural_texture", False)
    tex_type = scene_data.get("displace_texture_type", "NONE")
    
    if has_proc_tex:
        score += 15
        feedback.append(f"✅ Procedural texture used ({tex_type})")
    elif has_displace and tex_type != "NONE":
        # Maybe an image texture? Acceptable but not ideal based on prompt
        score += 5
        feedback.append(f"⚠️ Non-standard texture type used ({tex_type})")
    else:
        feedback.append("❌ No valid texture assigned to displacement")

    # --- Criterion 4: Material (10 pts) ---
    # Check color (should not be default grey) and roughness
    mat_color = scene_data.get("material_color", [0.8, 0.8, 0.8, 1.0])
    mat_rough = scene_data.get("material_roughness", 0.5)
    
    # Check if color is close to default grey (0.8, 0.8, 0.8)
    # Using a simple distance check
    def_col = [0.8, 0.8, 0.8]
    dist = math.sqrt(sum((mat_color[i] - def_col[i])**2 for i in range(3)))
    
    is_not_grey = dist > 0.1
    is_rough = mat_rough >= 0.5
    
    if is_not_grey and is_rough:
        score += 10
        feedback.append("✅ Material looks like terrain (colored and rough)")
    elif is_not_grey:
        score += 5
        feedback.append("⚠️ Material colored but too glossy")
    else:
        feedback.append("❌ Material is default grey")

    # --- Criterion 5: Camera Position (10 pts) ---
    cam_z = scene_data.get("camera_height", 0.0)
    if 5.0 <= cam_z <= 50.0:
        score += 10
        feedback.append(f"✅ Camera height good ({cam_z:.1f}m)")
    else:
        feedback.append(f"❌ Camera height out of range ({cam_z:.1f}m)")

    # --- Criterion 6: Render Output (20 pts) ---
    if render_exists and render_fresh:
        render_size_kb = result.get("render_size", 0) / 1024
        if render_size_kb > 50:
            score += 20
            feedback.append("✅ Render output exists and valid")
        else:
            score += 10
            feedback.append("⚠️ Render output exists but file size suspiciously small")
    else:
        feedback.append("❌ Render output missing or not created during task")

    # --- Criterion 7: Saved Blend File (10 pts) ---
    if result.get("blend_exists", False):
        score += 10
        feedback.append("✅ Blend file saved")
    else:
        feedback.append("❌ Blend file not saved")

    # --- Bonus: VLM Verification (5 pts) ---
    # Only if we have the render or a good final screenshot
    if query_vlm and render_exists:
        try:
            # We prefer checking the actual render file if possible, but the 
            # framework typically provides the final screenshot via `get_final_screenshot`.
            # If the agent opened the render result, it might be visible.
            # Or we can check the final screenshot of the viewport.
            final_screen = get_final_screenshot(traj)
            
            prompt = """
            Does this image show a 3D rendered terrain or landscape?
            Look for:
            1. Uneven, mountainous, or hilly geometry (not a flat plane).
            2. Natural colors (green, brown, grey rock) - NOT just a white/grey box.
            3. A view looking down at the ground.
            
            Return JSON: {"is_terrain": boolean, "reason": string}
            """
            
            vlm_res = query_vlm(image=final_screen, prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_terrain", False):
                    score += 5
                    feedback.append("✅ VLM confirms terrain visuals")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold
    # Must have displacement setup (approx 45 pts) + saved file or render
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }