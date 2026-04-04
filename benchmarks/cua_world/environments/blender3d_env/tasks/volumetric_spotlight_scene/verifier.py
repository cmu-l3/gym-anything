#!/usr/bin/env python3
"""
Verifier for Volumetric Spotlight Scene task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_volumetric_scene(traj, env_info, task_info):
    """
    Verifies the volumetric spotlight task based on:
    1. Scene Analysis (Blender Python export):
       - Spot light exists
       - Sun light removed/disabled
       - Volume domain (Principled Volume) exists
       - World background is dark
       - Render engine is Cycles
    2. Render Output:
       - File exists and was created during task
       - Size > 50KB
    """
    
    # 1. Setup - Copy result from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Data
    scene_data = result.get("scene_analysis", {})
    render_exists = result.get("render_exists", False)
    render_fresh = result.get("render_created_during_task", False)
    render_size = result.get("render_size_bytes", 0)
    blend_exists = result.get("blend_exists", False)
    
    if not scene_data.get("valid_blend", False):
        return {"passed": False, "score": 0, "feedback": "Could not analyze .blend file (corrupt or missing)."}

    # 3. Score Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Spot Light (20 pts)
    # Must have a Spot light
    if scene_data.get("has_spot"):
        score += 20
        feedback.append("✅ Spot light added.")
    else:
        feedback.append("❌ No Spot light detected.")
        
    # Criterion 2: Sun Removal (5 pts)
    if not scene_data.get("has_sun"):
        score += 5
        feedback.append("✅ Sun light removed.")
    else:
        feedback.append("❌ Sun light still active (scene will be too bright).")

    # Criterion 3: Volume Domain (20 pts)
    # Must have a mesh with Volume shader
    if scene_data.get("has_volume_domain"):
        score += 20
        feedback.append("✅ Volume domain detected.")
    else:
        feedback.append("❌ No volumetric shader found (Principled Volume).")

    # Criterion 4: Volume Density (10 pts)
    # Density between 0.01 and 1.0
    density = scene_data.get("volume_density", 0.0)
    if 0.01 <= density <= 1.0:
        score += 10
        feedback.append(f"✅ Volume density good ({density:.3f}).")
    elif scene_data.get("has_volume_domain"):
        feedback.append(f"⚠️ Volume density {density} might be too extreme.")
    
    # Criterion 5: Dark Background (10 pts)
    brightness = scene_data.get("world_brightness", 1.0)
    if brightness < 0.15:
        score += 10
        feedback.append("✅ World background is dark.")
    else:
        feedback.append(f"❌ World background too bright ({brightness:.2f}).")

    # Criterion 6: Render Engine (5 pts)
    engine = scene_data.get("render_engine", "UNKNOWN")
    if engine == 'CYCLES':
        score += 5
        feedback.append("✅ Cycles engine selected.")
    else:
        feedback.append(f"❌ Render engine is {engine} (Cycles recommended for volumetrics).")

    # Criterion 7: Render Output (20 pts)
    if render_exists and render_fresh and render_size > 50000:
        score += 20
        feedback.append("✅ Valid render output found.")
    elif render_exists and not render_fresh:
        feedback.append("❌ Render file exists but is old (stale data).")
    elif render_exists and render_size < 50000:
        feedback.append("❌ Render file exists but is suspiciously small (blank?).")
    else:
        feedback.append("❌ No render output found.")

    # Criterion 8: Blend File Saved (10 pts)
    if blend_exists:
        score += 10
        feedback.append("✅ Project file saved.")
    else:
        feedback.append("❌ Project file not saved.")

    # 4. Final Result
    passed = score >= 70
    
    # Optional VLM Check (Bonus/Verification)
    # If we had access to VLM here, we'd check if the image looks foggy/moody.
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }