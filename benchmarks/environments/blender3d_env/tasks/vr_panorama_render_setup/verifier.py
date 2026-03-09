#!/usr/bin/env python3
"""
Verifier for vr_panorama_render_setup task.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vr_panorama_setup(traj, env_info, task_info):
    """
    Verifies that the agent configured the scene for VR rendering.
    
    Criteria:
    1. Camera is Panoramic Equirectangular (40 pts)
    2. Resolution is 2:1 aspect ratio (15 pts)
    3. Render Engine is Cycles (10 pts)
    4. Camera is at correct location (15 pts)
    5. Valid render output file exists (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Result read failed: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    scene_data = result.get("scene_analysis", {})
    render_data = result.get("render_check", {})
    
    score = 0
    feedback = []
    
    # 2. Check File Validity
    if not scene_data.get("valid_file"):
        return {"passed": False, "score": 0, "feedback": "Failed: Project file not saved correctly."}

    # 3. Check Camera Configuration (40 pts)
    cam_type = scene_data.get("camera_type", "UNKNOWN")
    pano_type = scene_data.get("panorama_type", "UNKNOWN")
    
    if cam_type == 'PANO':
        score += 20
        feedback.append("Camera type is Panoramic (+20).")
    else:
        feedback.append(f"Camera type incorrect: {cam_type} (expected PANO).")

    if pano_type == 'EQUIRECTANGULAR':
        score += 20
        feedback.append("Panorama type is Equirectangular (+20).")
    else:
        feedback.append(f"Panorama type incorrect: {pano_type} (expected EQUIRECTANGULAR).")

    # 4. Check Resolution (15 pts)
    # Target: 2:1 aspect ratio, e.g., 2048x1024
    res_x = scene_data.get("resolution_x", 0)
    res_y = scene_data.get("resolution_y", 0)
    
    if res_y > 0 and res_x == (res_y * 2):
        score += 15
        feedback.append(f"Aspect ratio is correct 2:1 ({res_x}x{res_y}) (+15).")
    else:
        # Check if render output has correct dimensions even if scene settings differ (unlikely but possible)
        r_width = render_data.get("width", 0)
        r_height = render_data.get("height", 0)
        if r_height > 0 and r_width == (r_height * 2):
             score += 15
             feedback.append(f"Render output aspect ratio is correct 2:1 ({r_width}x{r_height}) (+15).")
        else:
             feedback.append(f"Resolution incorrect: {res_x}x{res_y} (Expected 2:1 aspect ratio).")

    # 5. Check Render Engine (10 pts)
    engine = scene_data.get("render_engine", "UNKNOWN")
    if engine == 'CYCLES':
        score += 10
        feedback.append("Render engine is Cycles (+10).")
    else:
        feedback.append(f"Render engine incorrect: {engine} (Expected CYCLES).")

    # 6. Check Camera Location (15 pts)
    # Target: [-5.0, 0.0, 1.5]
    loc = scene_data.get("location", [0, 0, 0])
    target = [-5.0, 0.0, 1.5]
    dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(loc, target)))
    
    if dist < 0.5: # 0.5 meter tolerance
        score += 15
        feedback.append("Camera location correct (+15).")
    else:
        feedback.append(f"Camera location off by {dist:.2f}m.")

    # 7. Check Render Output (20 pts)
    if render_data.get("exists") and render_data.get("created_during_task"):
        # Check size to ensure not empty/black (VR renders are usually large)
        if render_data.get("size_bytes", 0) > 50000: # >50KB
            score += 20
            feedback.append("Valid render file created (+20).")
        else:
            score += 5
            feedback.append("Render file created but strangely small (<50KB) (+5).")
    elif render_data.get("exists"):
        feedback.append("Render file exists but timestamp indicates it wasn't created during this task.")
    else:
        feedback.append("No render output file found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }