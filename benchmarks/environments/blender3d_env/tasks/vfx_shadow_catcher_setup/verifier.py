#!/usr/bin/env python3
"""
Verifier for vfx_shadow_catcher_setup task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vfx_shadow_catcher(traj, env_info, task_info):
    """
    Verifies that the agent set up a Shadow Catcher correctly.
    
    Criteria:
    1. Render Engine is Cycles (15 pts) - Required for Shadow Catcher in older Blender/robustness.
    2. Film Transparent Enabled (20 pts) - Essential for compositing.
    3. Shadow Catcher Enabled on GroundPlane (25 pts) - Core task.
    4. Valid Render Output (15 pts) - File exists.
    5. Render Analysis (25 pts) - Confirms image actually has transparency and shadows.
    
    Pass Threshold: 75/100
    """
    
    # 1. Retrieve Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    blend_data = data.get("blend_data", {})
    image_data = data.get("image_data", {})
    
    # Criterion 1: Render Engine (15 pts)
    engine = blend_data.get("engine", "UNKNOWN")
    if engine == 'CYCLES':
        score += 15
        feedback.append("✅ Render engine is Cycles (15/15)")
    else:
        feedback.append(f"❌ Render engine is {engine}, expected CYCLES (0/15)")
        
    # Criterion 2: Film Transparent (20 pts)
    if blend_data.get("film_transparent", False):
        score += 20
        feedback.append("✅ Film transparency enabled (20/20)")
    else:
        feedback.append("❌ Film transparency NOT enabled (0/20)")
        
    # Criterion 3: Shadow Catcher Object (25 pts)
    ground_exists = blend_data.get("ground_exists", False)
    is_catcher = blend_data.get("is_shadow_catcher", False)
    
    if ground_exists and is_catcher:
        score += 25
        feedback.append("✅ GroundPlane configured as Shadow Catcher (25/25)")
    elif ground_exists:
        feedback.append("❌ GroundPlane exists but Shadow Catcher NOT enabled (0/25)")
    else:
        feedback.append("❌ GroundPlane object missing (0/25)")
        
    # Criterion 4: Render Output Exists (15 pts)
    if data.get("render_exists", False) and image_data.get("exists", False):
        score += 15
        feedback.append("✅ Render output found (15/15)")
    else:
        feedback.append("❌ Render output file missing (0/15)")
        
    # Criterion 5: Image Analysis (25 pts)
    # We check the actual pixels to verify the result isn't just a blank transparent image or a solid image
    img_ok = False
    if image_data.get("exists", False):
        is_transparent = image_data.get("is_background_transparent", False)
        has_subject = image_data.get("has_opaque_subject", False)
        has_shadow = image_data.get("has_shadow_pixels", False)
        
        if is_transparent and has_subject and has_shadow:
            score += 25
            img_ok = True
            feedback.append("✅ Render has correct transparency and shadows (25/25)")
        else:
            reasons = []
            if not is_transparent: reasons.append("Background not transparent")
            if not has_subject: reasons.append("Car missing/invisible")
            if not has_shadow: reasons.append("No shadow pixels detected")
            feedback.append(f"❌ Render content invalid: {', '.join(reasons)} (0/25)")
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }