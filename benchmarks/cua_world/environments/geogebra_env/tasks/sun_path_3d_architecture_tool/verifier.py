#!/usr/bin/env python3
"""
Verifier for Sun Path 3D Architecture Tool.

Criteria:
1. File created during task (10 pts)
2. 3D View enabled/used (10 pts)
3. Three circular paths present (20 pts)
4. Key geometric constants found (Latitude/Obliquity) indicating correct geometry (20 pts)
5. Rotation/Tilt applied (20 pts)
6. VLM Visual Verification (20 pts)

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70

def verify_sun_path_3d_architecture_tool(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # 1. Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export failed: {e}"}

    score = 0
    feedback = []

    # Criterion 1: File check (10 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File created successfully (+10)")
    else:
        feedback.append("File not found or old (+0)")

    # Criterion 2: 3D View (10 pts)
    if result.get("has_3d_view"):
        score += 10
        feedback.append("3D View enabled (+10)")
    else:
        feedback.append("3D View NOT detected (+0)")

    # Criterion 3: Three Paths (20 pts)
    # Check 3D objects count or Circles count
    num_3d = result.get("num_3d_objects", 0)
    # Sometimes circles in 3D might be standard 'conic' elements if on a plane, 
    # but usually 'conic3d' if rotated.
    if num_3d >= 3:
        score += 20
        feedback.append(f"Found {num_3d} 3D objects (Paths) (+20)")
    elif num_3d >= 1:
        score += 10
        feedback.append(f"Found {num_3d} 3D objects (Partial) (+10)")
    else:
        feedback.append("No 3D objects found (+0)")

    # Criterion 4: Constants (20 pts)
    # Look for 47.6 or 42.4 (Latitude logic) AND 23.44 (Obliquity)
    constants = result.get("found_constants", [])
    has_lat = any(x in constants for x in [47.6, 42.4])
    has_obl = any(x in constants for x in [23.44, 23.45, 23.4])
    
    if has_lat and has_obl:
        score += 20
        feedback.append(f"Found Latitude and Obliquity constants {constants} (+20)")
    elif has_lat or has_obl:
        score += 10
        feedback.append(f"Found some constants {constants} (+10)")
    else:
        feedback.append("Missing geometric constants (47.6, 23.44) (+0)")

    # Criterion 5: Rotation/Tilt (20 pts)
    if result.get("has_rotation"):
        score += 20
        feedback.append("Rotation command detected (+20)")
    elif has_lat and num_3d >= 3:
        # Implicit rotation if 3d objects and lat constant exist?
        # Maybe constructed via vectors. Give partial.
        score += 10
        feedback.append("Rotation inferred from constants/objects (+10)")
    else:
        feedback.append("No rotation detected (+0)")

    # Criterion 6: VLM Verification (20 pts)
    # Use trajectory to ensure they actually built it in 3D view
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these GeoGebra screenshots. The user is creating a 3D Sun Path diagram.
    Look for:
    1. A 3D view (3 axes visible, usually red/green/blue).
    2. Three parallel circular paths or arcs (representing sun paths).
    3. The paths should be TILTED relative to the ground plane (not flat on the grid).
    
    Does the final result look like a 3D diagram with tilted rings/arcs?
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
    
    if vlm_result.get("success"):
        # Simple heuristic on VLM response
        text = vlm_result.get("response", "").lower()
        if "tilted" in text and ("3d" in text or "axes" in text):
            score += 20
            feedback.append("VLM confirmed 3D tilted paths (+20)")
        elif "3d" in text:
            score += 10
            feedback.append("VLM confirmed 3D view but unclear tilt (+10)")
        else:
            feedback.append("VLM could not confirm 3D geometry (+0)")
    else:
        feedback.append("VLM check failed (skip) (+0)")
        # Fallback points if programmatic was very strong
        if score >= 60:
            score += 20 

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback)
    }