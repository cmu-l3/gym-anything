#!/usr/bin/env python3
"""
Verifier for create_shelled_enclosure task.

Checks:
1. File existence and anti-gaming timestamps.
2. Geometry analysis (Pad, Shell features, dimensions, volume, face count).
3. VLM verification of the workflow (Sketch -> Pad -> Shell).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_shelled_enclosure(traj, env_info, task_info):
    """
    Verifies that the agent created a shelled enclosure in FreeCAD.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_dims = metadata.get('target_dims', [100.0, 60.0, 25.0])
    target_vol_range = metadata.get('target_volume_range', [20000, 35000])
    dim_tolerance = metadata.get('dim_tolerance', 2.0)

    # 1. Retrieve Programmatic Analysis Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criteria 1: File Basics (20 pts) ---
    if result.get('file_exists'):
        score += 10
        feedback.append("File exists")
        
        if result.get('file_created_during_task'):
            score += 5
            feedback.append("File created during task")
        else:
            feedback.append("File timestamp invalid (anti-gaming)")
            
        if result.get('is_valid_fcstd'):
            score += 5
            feedback.append("Valid FreeCAD format")
        else:
            feedback.append("Invalid FCStd file")
    else:
        feedback.append("File not found")
        return {"passed": False, "score": 0, "feedback": "File not found", "details": result}

    # --- Criteria 2: Geometry Analysis (65 pts) ---
    geom = result.get('geometry_analysis', {})
    
    # Feature checks
    if geom.get('has_pad'):
        score += 15
        feedback.append("Pad feature detected")
    else:
        feedback.append("Missing Pad feature")
        
    if geom.get('has_shell'):
        score += 25
        feedback.append("Shell/Thickness feature detected")
    else:
        feedback.append("Missing Shell/Thickness feature")

    # Dimension checks
    bbox = geom.get('bbox', [0, 0, 0])
    # Sort dimensions to be orientation agnostic
    bbox_sorted = sorted(bbox)
    target_sorted = sorted(target_dims)
    
    dims_match = True
    for b, t in zip(bbox_sorted, target_sorted):
        if abs(b - t) > dim_tolerance:
            dims_match = False
    
    if dims_match:
        score += 10  # Reduced weight, shared across dims
        feedback.append(f"Dimensions match {target_dims}")
    else:
        feedback.append(f"Dimensions mismatch: Got {bbox}, expected {target_dims}")

    # Volume check (Proxy for correct shelling)
    vol = geom.get('volume', 0)
    if target_vol_range[0] <= vol <= target_vol_range[1]:
        score += 10
        feedback.append(f"Volume correct ({int(vol)} mm^3)")
    else:
        feedback.append(f"Volume out of range ({int(vol)} mm^3) - check wall thickness")
        
    # Face count check (Solid=6, Shelled>6)
    if geom.get('faces', 0) > 6:
        score += 5
        feedback.append("Geometry is hollow (face count > 6)")
    else:
        feedback.append("Geometry appears solid (face count <= 6)")

    # --- Criteria 3: VLM Workflow Verification (15 pts) ---
    # We check if the agent actually used the GUI correctly
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from FreeCAD.
    I am looking for evidence of the following workflow:
    1. A Sketch being drawn (rectangle).
    2. A yellow "Pad" or extrusion being created.
    3. A "Thickness" or "Shell" operation where the top face is removed to make a box.
    4. The final result looking like an open grey box.
    
    Did the user perform these steps? Return JSON with boolean 'workflow_followed'.
    """
    
    vlm_passed = False
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("workflow_followed"):
            vlm_passed = True
            score += 15
            feedback.append("Visual workflow verified")
        else:
            feedback.append("Visual workflow verification failed")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if geometry is perfect, give benefit of doubt
        if score >= 85:
            score += 15
            feedback.append("VLM skipped (geometry perfect)")

    # --- Final Score ---
    passed = score >= 60 and geom.get('has_shell') and geom.get('has_pad')
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result
    }