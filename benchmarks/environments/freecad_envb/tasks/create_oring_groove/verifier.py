#!/usr/bin/env python3
"""
Verifier for create_oring_groove task.

Scoring Criteria (Total 100):
1. File Validity (10 pts): File exists and modified during task.
2. Feature Tree (20 pts): Contains Body, Pad, and Groove features.
3. Geometry (50 pts):
   - Volume within tolerance (20 pts)
   - Bounding Box matches 20x20x60 (15 pts)
   - Cross-section check confirms material removed at Z=15 (15 pts)
4. Visual Verification (20 pts): VLM confirms visual appearance of shaft with groove.
"""

import json
import os
import tempfile
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_oring_groove(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume_mm3', 18631.7)
    vol_tol = expected_vol * (metadata.get('volume_tolerance_percent', 5) / 100.0)
    
    score = 0
    feedback_parts = []
    
    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. File Validity Checks (10 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task."}

    # 3. Geometry Analysis (70 pts total split across tree and geo)
    geo = result.get("geometry_analysis", {})
    if geo.get("error"):
        feedback_parts.append(f"Geometry analysis warning: {geo['error']}")
    
    # Feature Tree (20 pts)
    features = geo.get("features", [])
    has_body = "Body" in features
    has_pad = "Pad" in features
    has_groove = "Groove" in features
    
    if has_body: score += 5
    if has_pad: score += 5
    if has_groove: 
        score += 10
        feedback_parts.append("Groove feature detected in tree.")
    else:
        feedback_parts.append("Groove feature missing from tree.")

    # Geometric Properties (50 pts)
    # Volume Check (20 pts)
    actual_vol = geo.get("volume", 0)
    if abs(actual_vol - expected_vol) <= vol_tol:
        score += 20
        feedback_parts.append(f"Volume correct ({actual_vol:.1f} mm³).")
    elif abs(actual_vol - expected_vol) <= vol_tol * 3:
        score += 10 # Partial credit
        feedback_parts.append(f"Volume roughly correct ({actual_vol:.1f} mm³).")
    else:
        feedback_parts.append(f"Volume incorrect ({actual_vol:.1f} vs {expected_vol:.1f}).")

    # Bounding Box Check (15 pts)
    bbox = geo.get("bbox", [0,0,0])
    # Dimensions should be approx 20, 20, 60 (sorted)
    dims = sorted(bbox)
    # Expect [20, 20, 60] roughly
    if (19.0 <= dims[0] <= 21.0 and 
        19.0 <= dims[1] <= 21.0 and 
        59.0 <= dims[2] <= 61.0):
        score += 15
        feedback_parts.append("Dimensions correct.")
    else:
        feedback_parts.append(f"Dimensions incorrect: {dims}")

    # Cross-section/Groove Physical Check (15 pts)
    if geo.get("groove_check"):
        score += 15
        feedback_parts.append("Groove physically confirmed via cross-section.")
    else:
        feedback_parts.append("Groove NOT detected in geometry check.")

    # 4. VLM Visual Verification (20 pts)
    # Use trajectory frames to confirm visual appearance
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = """
        Analyze this screenshot of FreeCAD.
        1. Is there a 3D cylindrical object visible?
        2. Does the cylinder have a groove or indentation cut into it around the circumference?
        3. Does the object look like a mechanical shaft?
        
        Respond JSON: {"cylinder_visible": bool, "groove_visible": bool, "looks_correct": bool}
        """
        try:
            vlm_res = query_vlm(image=final_screenshot, prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("cylinder_visible"): vlm_score += 5
            if parsed.get("groove_visible"): vlm_score += 10
            if parsed.get("looks_correct"): vlm_score += 5
            
            score += vlm_score
            if vlm_score >= 15:
                feedback_parts.append("Visual check passed.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Grant partial points if geometry passed significantly, assuming VLM error
            if score >= 60: score += 10 

    passed = score >= 60 and has_groove and geo.get("groove_check")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }