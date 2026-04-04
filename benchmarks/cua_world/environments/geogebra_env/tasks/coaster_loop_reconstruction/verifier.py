#!/usr/bin/env python3
"""
Verifier for Coaster Loop Reconstruction task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_coaster_loop_reconstruction(traj, env_info, task_info):
    """
    Verify the coaster loop reconstruction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}
    
    # Load result
    tmp_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
            
    score = 0
    feedback = []
    
    # 1. File existence (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created (+10)")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found but old timestamp (+5)")
    else:
        feedback.append("File not found")
        
    # 2. Image Import (15 pts)
    if result.get("has_image"):
        score += 15
        feedback.append("Image imported (+15)")
    else:
        feedback.append("No image found in file")
        
    # 3. Clothoid Logic (30 pts)
    # Requires integrals of trig functions or Fresnel
    if result.get("has_integrals"):
        score += 30
        feedback.append("Clothoid/Fresnel integrals detected (+30)")
    elif result.get("has_curve"):
        # partial credit for just a curve without clear clothoid math
        score += 10
        feedback.append("Generic curve found, but clothoid math not detected (+10)")
    else:
        feedback.append("No parametric curve found")
        
    # 4. Curve Object (15 pts)
    if result.get("has_curve"):
        score += 15
        feedback.append("Curve object present (+15)")
        
    # 5. Height/Scale (30 pts split)
    # 15 for text label existing
    if result.get("has_height_text"):
        score += 15
        feedback.append("Height label found (+15)")
        
        # 15 for reasonable value (15m - 60m is typical for loops)
        h = result.get("reported_height", 0)
        if 15.0 <= h <= 60.0:
            score += 15
            feedback.append(f"Height value {h}m is realistic (+15)")
        elif h > 0:
            score += 5
            feedback.append(f"Height {h}m is outside typical range (15-60m) (+5)")
    else:
        feedback.append("No height text label found")
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }