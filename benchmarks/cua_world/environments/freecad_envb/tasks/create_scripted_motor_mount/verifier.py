#!/usr/bin/env python3
"""
Verifier for create_scripted_motor_mount task.
Verifies geometry accuracy and evidence of scripting.
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_scripted_motor_mount(traj, env_info, task_info):
    """
    Verify the motor mount plate creation.
    
    Criteria:
    1. File creation (10 pts)
    2. Valid Solid Geometry (20 pts)
    3. Dimensional Accuracy (BBox) (20 pts)
    4. Feature Accuracy (Volume & Holes) (30 pts)
    5. Scripting Evidence (VLM + Logs) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_vol = metadata.get('target_volume', 47445.8)
    vol_tol_pct = metadata.get('volume_tolerance_percent', 5.0)
    target_bbox = metadata.get('bbox', [120.0, 80.0, 5.0])
    bbox_tol = metadata.get('bbox_tolerance', 1.0)
    
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
            
    score = 0
    feedback_parts = []
    
    # 1. File Check (10 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not created during task."}

    # 2. Valid Solid Check (20 pts)
    geo = result.get('geometry', {})
    if geo.get('valid_solid') and geo.get('is_valid'):
        score += 20
        feedback_parts.append("Valid solid geometry found.")
    else:
        feedback_parts.append("Geometry error: No valid solid found.")
        # If no solid, we can't check dims, so return current score (max 10)
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}
        
    # 3. Dimensions Check (20 pts)
    bbox = geo.get('bbox', [0, 0, 0])
    # Sort bbox dims to handle rotation (e.g., 120x5x80 is same as 120x80x5)
    bbox_sorted = sorted(bbox)
    target_sorted = sorted(target_bbox)
    
    dims_ok = True
    for i in range(3):
        if abs(bbox_sorted[i] - target_sorted[i]) > bbox_tol:
            dims_ok = False
            break
            
    if dims_ok:
        score += 20
        feedback_parts.append(f"Dimensions correct ({bbox}).")
    else:
        feedback_parts.append(f"Dimensions incorrect: found {bbox}, expected {target_bbox}.")

    # 4. Features & Volume Check (30 pts)
    vol = geo.get('volume', 0)
    vol_diff_pct = abs(vol - target_vol) / target_vol * 100
    
    cyl_faces = geo.get('cyl_faces', 0)
    
    if vol_diff_pct <= vol_tol_pct:
        score += 15
        feedback_parts.append(f"Volume accurate ({vol:.1f} mm³).")
    else:
        feedback_parts.append(f"Volume mismatch ({vol:.1f} vs {target_vol}).")
        
    if cyl_faces >= 5:
        score += 15
        feedback_parts.append(f"Holes detected ({cyl_faces} cylindrical faces).")
    else:
        feedback_parts.append(f"Missing holes (found {cyl_faces} cylindrical faces, expected >= 5).")

    # 5. Scripting Evidence (20 pts)
    # Part A: Log evidence (10 pts)
    if result.get('script_evidence_found'):
        score += 10
        feedback_parts.append("Script usage detected in logs.")
    else:
        feedback_parts.append("No script commands found in log.")
        
    # Part B: VLM Trajectory Check (10 pts)
    # Check if python console was visible/used
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    if final_img:
        frames.append(final_img)
        
    vlm_prompt = """
    Review these screenshots of a FreeCAD task. 
    The user was instructed to use the Python Console (bottom panel usually) to script the geometry.
    1. Do you see the Python Console panel open? (Usually at the bottom, with '>>>' prompts or code text)
    2. Do you see text/code being typed into it?
    3. Does the final 3D view show a rectangular plate with 5 holes?
    
    Return JSON: {"python_console_visible": bool, "code_entry_visible": bool, "plate_visible": bool}
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('python_console_visible') or parsed.get('code_entry_visible'):
            score += 10
            feedback_parts.append("VLM confirms Python console usage.")
        elif result.get('script_evidence_found'):
            # If VLM missed it but logs caught it, give full points
            score += 10
        else:
            feedback_parts.append("VLM did not see Python console usage.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if log evidence was found, grant these points anyway to be generous
        if result.get('script_evidence_found'):
            score += 10

    passed = score >= 60 and geo.get('valid_solid')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }