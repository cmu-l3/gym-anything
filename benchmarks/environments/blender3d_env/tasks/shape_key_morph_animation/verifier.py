#!/usr/bin/env python3
"""
Verifier for shape_key_morph_animation task.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shape_key_morph_animation(traj, env_info, task_info):
    """
    Verify the shape key morphing task.
    
    Criteria:
    1. File Saved & Modified (15 pts)
    2. Shape Keys Exist (Basis + 2 others) (20 pts)
    3. Vertex Displacement is Real (Anti-gaming) (20 pts)
    4. Animation Keyframes Exist (25 pts)
    5. Frame Range Correct (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback_parts = []
    
    # 1. File Check (15 pts)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if result.get("file_modified_during_task"):
        score += 15
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("File exists but not modified")
        
    analysis = result.get("analysis", {})
    if "error" in analysis:
        return {"passed": False, "score": score, "feedback": f"Analysis failed: {analysis['error']}"}

    # 2. Shape Keys Exist (20 pts)
    sk_count = analysis.get("shape_key_count", 0)
    if sk_count >= 3:
        score += 20
        feedback_parts.append(f"Shape keys found ({sk_count})")
    elif sk_count >= 2:
        score += 10
        feedback_parts.append(f"Partial shape keys ({sk_count}/3)")
    else:
        feedback_parts.append("Insufficient shape keys")

    # 3. Vertex Displacement (20 pts)
    # Check if keys actually morph the mesh (avg displacement > 0.1)
    displacements = analysis.get("vertex_displacements", {})
    valid_keys = 0
    for key_name, data in displacements.items():
        if data.get("avg", 0) > 0.1 and data.get("nonzero_count", 0) > 10:
            valid_keys += 1
    
    # Check similarity (should be low if they are different shapes)
    similarity = analysis.get("displacement_similarity", 1.0)
    distinct = similarity < 0.95
    
    if valid_keys >= 2 and distinct:
        score += 20
        feedback_parts.append("Valid distinct morphs")
    elif valid_keys >= 2:
        score += 15
        feedback_parts.append("Morphs exist but look similar")
    elif valid_keys > 0:
        score += 10
        feedback_parts.append("One valid morph")
    else:
        feedback_parts.append("Shape keys have no effect")

    # 4. Animation (25 pts)
    has_anim = analysis.get("has_animation_data")
    fcurves = analysis.get("fcurve_details", [])
    valid_fcurves = 0
    
    # Check for meaningful animation (at least 2 keyframes per curve)
    for fc in fcurves:
        if fc.get("point_count", 0) >= 2:
            valid_fcurves += 1
            
    if has_anim and valid_fcurves >= 2:
        score += 25
        feedback_parts.append("Animation keyframes confirmed")
    elif has_anim:
        score += 10
        feedback_parts.append("Animation data exists but incomplete")
    else:
        feedback_parts.append("No animation data")

    # 5. Frame Range (20 pts)
    f_start = analysis.get("frame_start")
    f_end = analysis.get("frame_end")
    if f_start == 1 and (55 <= f_end <= 65):
        score += 20
        feedback_parts.append("Frame range correct")
    elif f_end != 250: # Default is 250
        score += 10
        feedback_parts.append(f"Frame range adjusted ({f_start}-{f_end})")
    else:
        feedback_parts.append("Frame range default")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }