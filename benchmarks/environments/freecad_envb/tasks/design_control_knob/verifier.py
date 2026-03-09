#!/usr/bin/env python3
"""
Verifier for design_control_knob task.
Analyzes the geometric properties extracted from the FreeCAD model.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_control_knob(traj, env_info, task_info):
    """
    Verifies the control knob design based on:
    1. File existence and valid geometry
    2. Bounding Box dimensions (25x25x17)
    3. Volume (approx 4284 mm^3)
    4. Center of Mass Z (approx 6.5 mm)
    5. Feature usage (Pad, Pocket, Fillet)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_vol = metadata.get('target_volume_mm3', 4284.0)
    vol_tol = metadata.get('volume_tolerance', 200.0)
    
    target_bbox = [
        metadata.get('target_bbox_x', 25.0),
        metadata.get('target_bbox_y', 25.0),
        metadata.get('target_bbox_z', 17.0)
    ]
    bbox_tol = metadata.get('bbox_tolerance', 1.0)
    
    target_com_z = metadata.get('target_com_z', 6.5)
    com_tol = metadata.get('com_z_tolerance', 1.5)

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "File not found at ~/Documents/FreeCAD/control_knob.FCStd"}
    
    if not result.get("created_during_task"):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task session."}

    analysis = result.get("analysis", {})
    if not analysis or analysis.get("error"):
        return {"passed": False, "score": 10, "feedback": f"File exists but could not be analyzed: {analysis.get('error')}"}

    score = 0
    feedback = []

    # 1. Valid Solid (10 pts)
    if analysis.get("valid_solid"):
        score += 10
    else:
        feedback.append("Model is not a valid solid.")

    # 2. Bounding Box (20 pts)
    # Check dimensions (order independent for X/Y, Z should be height)
    agent_bbox = sorted(analysis.get("bbox", [0,0,0]))
    # Expected: 25, 25, 17. Sorted: 17, 25, 25
    expected_sorted = sorted(target_bbox)
    
    bbox_ok = True
    for a, e in zip(agent_bbox, expected_sorted):
        if abs(a - e) > bbox_tol:
            bbox_ok = False
            break
            
    if bbox_ok:
        score += 20
    else:
        feedback.append(f"Dimensions incorrect. Expected ~25x25x17, got {[round(x,1) for x in agent_bbox]}.")

    # 3. Volume (30 pts)
    vol = analysis.get("volume", 0)
    if abs(vol - target_vol) <= vol_tol:
        score += 30
    else:
        feedback.append(f"Volume mismatch. Expected ~{target_vol}, got {round(vol,1)}.")

    # 4. Center of Mass Z (20 pts)
    # Z is usually the last element if we assume standard orientation
    com = analysis.get("com", [0,0,0])
    com_z = com[2] 
    
    # Check if Z is plausible. If user built it sideways, Z might be X or Y.
    # But instructions said "Skirt on XY plane... extending Z=0 to Z=5".
    if abs(com_z - target_com_z) <= com_tol:
        score += 20
    else:
        feedback.append(f"Center of Mass Z incorrect. Expected ~{target_com_z}, got {round(com_z,1)}.")

    # 5. Features (20 pts)
    features = analysis.get("features", [])
    required = ["Pad", "Pocket", "Fillet"]
    # Relaxed check: look for substrings
    found_count = 0
    for req in required:
        if any(req in f for f in features):
            found_count += 1
    
    feat_score = int((found_count / len(required)) * 20)
    score += feat_score
    if found_count < len(required):
        feedback.append(f"Missing features. Found: {features}")

    # Final tally
    passed = score >= 70
    feedback_str = " | ".join(feedback) if feedback else "Perfect execution."
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str,
        "details": analysis
    }