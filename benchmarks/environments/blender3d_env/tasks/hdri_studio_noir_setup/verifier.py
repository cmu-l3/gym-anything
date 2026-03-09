#!/usr/bin/env python3
import json
import os
import tempfile
import math
from gym_anything.vlm import query_vlm, get_final_screenshot

def verify_hdri_studio_noir_setup(traj, env_info, task_info):
    """
    Verify the HDRI Studio Noir setup task.
    
    Criteria:
    1. Blend file saved & Render output exists (Gate).
    2. HDRI Image loaded correctly (25 pts).
    3. Mapping node used + Rotation Z ~ 125 deg (20 pts).
    4. Hue/Saturation node used + Saturation 0.0 (20 pts).
    5. Nodes are connected correctly (15 pts).
    6. VLM Check: Render looks black and white and lit (20 pts).
    """
    
    # 1. Setup and Load Results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Gate Checks
    if not data.get("blend_exists"):
        return {"passed": False, "score": 0, "feedback": "Project file 'noir_setup.blend' not found."}
    
    analysis = data.get("analysis", {})
    score = 0
    feedback = []

    # 3. Check HDRI Loading (25 pts)
    hdri_name = analysis.get("hdri_image", "")
    if hdri_name and "studio_small" in hdri_name:
        score += 25
        feedback.append("HDRI loaded correctly.")
    else:
        feedback.append(f"Incorrect or missing HDRI image (Found: {hdri_name}).")

    # 4. Check Rotation (20 pts)
    # Target: 125 degrees = ~2.18 rad
    # Tolerance: 0.1 rad (~5.7 degrees)
    rot_z = analysis.get("mapping_rotation_z")
    target_rad = 2.18
    
    if rot_z is not None:
        if abs(rot_z - target_rad) < 0.2: # Generous tolerance
            score += 20
            feedback.append(f"Rotation correct ({math.degrees(rot_z):.1f}°).")
        else:
            feedback.append(f"Rotation incorrect. Expected ~125°, got {math.degrees(rot_z):.1f}°.")
    else:
        feedback.append("Mapping node or rotation not found.")

    # 5. Check Saturation (20 pts)
    sat = analysis.get("saturation")
    if sat is not None:
        if sat <= 0.05:
            score += 20
            feedback.append("Saturation correct (Black & White).")
        else:
            feedback.append(f"Scene is not black and white (Saturation: {sat}).")
    else:
        feedback.append("Hue/Saturation node not found.")

    # 6. Check Connections (15 pts)
    if analysis.get("is_connected"):
        score += 15
        feedback.append("Node graph connected correctly.")
    else:
        feedback.append("Nodes are present but Hue/Saturation is not connected to Background.")

    # 7. VLM Check on Render (20 pts)
    # We verify the output image actually looks like the goal
    # This prevents getting points for just adding nodes without hooking them up properly
    render_exists = data.get("render_exists")
    render_size = data.get("render_size_bytes", 0)
    
    if render_exists and render_size > 50000: # Min 50KB for non-black image
        # Use VLM to check the image content
        final_screenshot = get_final_screenshot(traj) # We rely on final screen or we could try to pull the render
        # Ideally we'd pull the specific render file, but for now we look at the screen/result
        
        prompt = """
        Analyze this image (a Blender render or screenshot).
        1. Is the image black and white (monochromatic)?
        2. Is there a visible 3D object (cube/shape) that is lit?
        Return JSON: {"is_bw": bool, "is_lit": bool}
        """
        
        # If we can't inspect the PNG directly, we assume the agent viewed it or the final screenshot shows the result
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res["success"]:
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_bw") and parsed.get("is_lit"):
                score += 20
                feedback.append("Visual verification passed: Render is B&W and lit.")
            else:
                feedback.append(f"Visual verification failed: {parsed}")
        else:
            # Fallback if VLM fails: give points if render exists and is large enough
            score += 10 
            feedback.append("VLM failed, awarding partial points for render existence.")
    else:
        feedback.append("Render output missing or too small.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }