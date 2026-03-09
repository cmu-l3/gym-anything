#!/usr/bin/env python3
"""
Verifier for create_staircase_array task.

Verifies:
1. File existence and creation time.
2. Geometric properties (Volume, Bounding Box) calculated inside the container.
3. Visual appearance using VLM (trajectory/final screenshot).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_staircase_array(traj, env_info, task_info):
    """
    Verify the staircase creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('total_vol', 504000000)
    vol_tolerance = metadata.get('tolerance_vol_percent', 5) / 100.0
    expected_bbox = metadata.get('expected_bbox', [1000, 2800, 1800])
    bbox_tolerance = metadata.get('tolerance_bbox_mm', 100)

    # 1. Retrieve result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback = []
    
    # 2. Check File Existence & Freshness (20 pts)
    if result_data.get('output_exists') and result_data.get('file_created_during_task'):
        score += 20
        feedback.append("File created successfully.")
    elif result_data.get('output_exists'):
        score += 10
        feedback.append("File exists but timestamp is suspicious.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'staircase.FCStd' not found."}

    # 3. Check Geometry (50 pts)
    geo = result_data.get('geometry', {})
    if not geo.get('valid_file'):
        feedback.append("File is not a valid FreeCAD document.")
    else:
        # Volume Check (30 pts)
        actual_vol = geo.get('volume_mm3', 0)
        vol_error = abs(actual_vol - expected_vol) / expected_vol if expected_vol > 0 else 1.0
        
        if vol_error <= vol_tolerance:
            score += 30
            feedback.append(f"Volume correct ({actual_vol:.0f} mm³).")
        elif vol_error <= (vol_tolerance * 2):
            score += 15
            feedback.append(f"Volume slightly off ({actual_vol:.0f} mm³).")
        else:
            feedback.append(f"Volume incorrect. Expected ~{expected_vol:.0f}, got {actual_vol:.0f}.")

        # Bounding Box Check (20 pts)
        actual_bbox = geo.get('bbox_mm', [0, 0, 0])
        # Sort dimensions to be orientation-agnostic, though staircase implies specific orientation
        # The task specifies X=Width, Y=Run, Z=Rise, so we should check specific indices if possible.
        # But to be generous, we'll check if the set of dimensions matches.
        # However, a staircase is distinct: 1000, 2800, 1800.
        
        dims_match = True
        for i, target in enumerate(expected_bbox):
            if abs(actual_bbox[i] - target) > bbox_tolerance:
                dims_match = False
                break
        
        if dims_match:
            score += 20
            feedback.append("Dimensions/Bounding Box correct.")
        else:
            feedback.append(f"Dimensions incorrect. Got {actual_bbox}, expected {expected_bbox}.")

    # 4. Visual Verification via VLM (30 pts)
    # Using trajectory frames to verify the process
    frames = sample_trajectory_frames(traj, n=3)
    final_img = get_final_screenshot(traj)
    
    if final_img:
        # Construct VLM Prompt
        prompt = """
        You are an architectural CAD verifier. 
        Task: Create a straight staircase with 10 steps.
        
        Look at the images. 
        1. Do you see a 3D model of a staircase (zigzag/stepped profile)?
        2. Does it look like a single continuous flight (not scattered blocks)?
        3. Are there approximately 10 steps?
        
        Answer JSON: {"is_staircase": bool, "continuous": bool, "approx_step_count": int, "confidence": float}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_img])
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('is_staircase'):
                score += 15
                feedback.append("Visual check: Staircase shape detected.")
                
                if parsed.get('continuous'):
                    score += 10
                    feedback.append("Visual check: Continuous flight.")
                
                # Bonus for count accuracy
                est_count = parsed.get('approx_step_count', 0)
                if 8 <= est_count <= 12:
                    score += 5
                    feedback.append("Visual check: Step count looks correct.")
            else:
                feedback.append("Visual check: Did not recognize a staircase structure.")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if geometry was perfect, give partial points
            if score >= 70:
                score += 10
                feedback.append("VLM skipped, assuming visual correctness based on perfect geometry.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }