#!/usr/bin/env python3
"""
Verifier for ocean_seascape_render task.

Scoring Criteria:
1. Ocean Modifier Setup (20 pts) - Presence + Resolution >= 10
2. Ocean Scale (10 pts) - Size between 20m and 200m
3. Environment/World (15 pts) - Warm/Sunset colors
4. Lighting (15 pts) - Sun light present and angled (not noon)
5. Camera (10 pts) - Valid height (0.5m - 15m)
6. Render Output (20 pts) - File exists, size > 50KB, created during task
7. File Saved (10 pts) - Blend file exists

Total: 100 pts
Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ocean_seascape(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    scene_data = result.get("scene_data", {})
    
    # Criterion 1: Ocean Modifier (20 pts)
    if scene_data.get("has_ocean_modifier"):
        res = scene_data.get("ocean_resolution", 0)
        if res >= 10:
            score += 20
            feedback.append("✅ Ocean modifier present with good detail")
        else:
            score += 10
            feedback.append(f"⚠️ Ocean modifier found but resolution low ({res} < 10)")
    else:
        feedback.append("❌ No Ocean modifier found on any mesh")

    # Criterion 2: Ocean Scale (10 pts)
    size = scene_data.get("ocean_size", 0)
    if 20 <= size <= 200:
        score += 10
        feedback.append("✅ Ocean scale is realistic")
    elif scene_data.get("has_ocean_modifier"):
        feedback.append(f"⚠️ Ocean scale {size}m is outside ideal range (20-200m)")

    # Criterion 3: World Background (15 pts)
    if scene_data.get("world_color_warm"):
        score += 15
        feedback.append("✅ World background set to sunset tones")
    else:
        rgb = scene_data.get("world_color_rgb", [0,0,0])
        feedback.append(f"❌ World background not warm/sunset color (RGB: {rgb})")

    # Criterion 4: Lighting (15 pts)
    if scene_data.get("has_sun_light"):
        if scene_data.get("sun_low_angle"):
            score += 15
            feedback.append("✅ Sun light positioned for sunset")
        else:
            score += 10
            feedback.append("⚠️ Sun light exists but is pointing straight down (noon)")
    else:
        feedback.append("❌ No Sun light found")

    # Criterion 5: Camera (10 pts)
    if scene_data.get("camera_valid"):
        height = scene_data.get("camera_height", 0)
        if 0.5 <= height <= 15.0:
            score += 10
            feedback.append("✅ Camera height is cinematic")
        else:
            score += 5
            feedback.append(f"⚠️ Camera height {height:.1f}m outside ideal range")
    else:
        feedback.append("❌ No active camera found")

    # Criterion 6: Render Output (20 pts)
    if result.get("render_exists") and result.get("render_new"):
        size_kb = result.get("render_size", 0) / 1024
        if size_kb > 50:
            score += 20
            feedback.append(f"✅ Render output valid ({size_kb:.1f} KB)")
        else:
            score += 5
            feedback.append(f"⚠️ Render output too small ({size_kb:.1f} KB)")
    else:
        feedback.append("❌ Render output missing or not created during task")

    # Criterion 7: File Saved (10 pts)
    if result.get("scene_exists"):
        score += 10
        feedback.append("✅ Blend file saved")
    else:
        feedback.append("❌ Blend file missing")

    # VLM Sanity Check (Bonus/Confirmation)
    # If the programmatic score is high, we verify visually to prevent hacking
    final_screenshot = get_final_screenshot(traj)
    if score >= 60 and final_screenshot and query_vlm:
        prompt = "Does this image show a 3D rendered ocean scene with sunset lighting? Answer yes or no."
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_res.get("success"):
            answer = vlm_res.get("response", "").lower()
            if "no" in answer and "yes" not in answer:
                score = max(0, score - 20)
                feedback.append("⚠️ VLM Flag: Image does not look like an ocean sunset")
            else:
                feedback.append("✅ VLM Confirmed visual content")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }