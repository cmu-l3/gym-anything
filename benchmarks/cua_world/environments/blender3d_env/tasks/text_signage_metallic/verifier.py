#!/usr/bin/env python3
"""
Verifier for text_signage_metallic task.

Criteria:
1. Text Object 'OPEN' Exists (20 pts)
2. Text Extrusion & Bevel Correct (25 pts)
3. Material Properties (Gold/Metallic) (20 pts)
4. Base Cube Deleted (5 pts)
5. Render Output Valid (15 pts)
6. VLM Visual Verification (15 pts)

Pass threshold: 70/100
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_text_signage(traj, env_info, task_info):
    """
    Verify the 3D text signage task using programmatic scene analysis and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # Extract data
    scene = result.get("scene_analysis", {})
    text_objects = scene.get("text_objects", [])
    render_exists = result.get("render_exists", False)
    render_fresh = result.get("render_created_during_task", False)
    render_size = result.get("render_size_kb", 0)

    # 1. Check Text Object Content (20 pts)
    target_text_obj = None
    for obj in text_objects:
        if "OPEN" in obj.get("body", "").upper():
            target_text_obj = obj
            break
    
    if target_text_obj:
        score += 20
        feedback.append("✅ Found 'OPEN' text object.")
    elif text_objects:
        # Found text but wrong content
        score += 5
        feedback.append(f"⚠️ Found text object '{text_objects[0].get('body')}', expected 'OPEN'.")
    else:
        feedback.append("❌ No text object found.")

    # 2. Check Geometry: Extrude & Bevel (25 pts)
    if target_text_obj:
        extrude = target_text_obj.get("extrude", 0)
        bevel = target_text_obj.get("bevel_depth", 0)
        
        # Extrude check (Target 0.15, allow 0.05-0.5)
        if 0.05 <= extrude <= 0.5:
            score += 15
            feedback.append(f"✅ Extrusion ({extrude:.2f}) within range.")
        else:
            feedback.append(f"❌ Extrusion ({extrude:.2f}) out of range (0.05-0.5).")
            
        # Bevel check (Target > 0)
        if bevel > 0.001:
            score += 10
            feedback.append("✅ Bevel applied.")
        else:
            feedback.append("❌ No bevel applied.")

    # 3. Check Material: Gold Metallic (20 pts)
    material_ok = False
    if target_text_obj:
        materials = target_text_obj.get("materials", [])
        for mat in materials:
            metallic = mat.get("metallic", 0)
            roughness = mat.get("roughness", 1)
            color = mat.get("base_color", [0,0,0,1])
            
            # Gold approximation: High Red, Med Green, Low Blue
            is_gold_color = (color[0] > 0.6 and color[1] > 0.4 and color[2] < 0.4)
            is_metallic = (metallic >= 0.8)
            is_smooth = (0.1 <= roughness <= 0.6)
            
            if is_metallic and is_gold_color and is_smooth:
                score += 20
                material_ok = True
                feedback.append("✅ Material is Metallic Gold.")
                break
            elif is_metallic:
                score += 10
                feedback.append("⚠️ Material is Metallic but color/roughness off.")
                material_ok = True  # Partial credit prevents full fail
                break
                
    if not material_ok and target_text_obj:
        feedback.append("❌ Material not metallic gold.")

    # 4. Base Cube Deleted (5 pts)
    if not scene.get("base_cube_exists", True):
        score += 5
        feedback.append("✅ BaseCube deleted.")
    else:
        feedback.append("❌ BaseCube still in scene.")

    # 5. Render Output (15 pts)
    if render_exists and render_fresh and render_size > 50:
        score += 15
        feedback.append("✅ Valid render output found.")
    elif render_exists:
        score += 5
        feedback.append("⚠️ Render exists but might be stale or empty.")
    else:
        feedback.append("❌ No render output.")

    # 6. VLM Verification (15 pts)
    # Use final screenshot from trajectory if render file fetch fails, or verify the render file itself
    vlm_score = 0
    if query_vlm:
        final_screen = get_final_screenshot(traj)
        
        # We prefer to check the actual render file if possible, but for simplicity
        # and robustness (since copy_from_env is for files), we use the final screenshot
        # of the desktop which should show the render result window or the viewport.
        
        prompt = """
        Review this screenshot of Blender.
        1. Is there 3D text visible that says "OPEN"?
        2. Does the text look metallic or gold?
        3. Is the text beveled/3D (not flat)?
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_screen)
            response = vlm_res.get("response", "").lower()
            
            if "open" in response and "yes" in response:
                vlm_score += 5
            if "metallic" in response or "gold" in response:
                vlm_score += 5
            if "3d" in response or "bevel" in response:
                vlm_score += 5
                
            score += vlm_score
            feedback.append(f"✅ VLM Verification: {vlm_score}/15 pts")
        except Exception as e:
            feedback.append(f"⚠️ VLM Error: {e}")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }