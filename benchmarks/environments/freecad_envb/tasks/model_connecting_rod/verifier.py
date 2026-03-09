#!/usr/bin/env python3
"""
Verifier for model_connecting_rod task.

Verifies:
1. File existence and validity.
2. Geometric properties (Bounding box, Holes).
3. VLM verification for visual confirmation of the I-beam shape.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_connecting_rod(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Get programmatic results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 3. Analyze Programmatic Metrics
    score = 0
    feedback = []
    
    file_exists = result_data.get("file_exists", False)
    geometry = result_data.get("geometry", {})
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "File connecting_rod.FCStd not found."}
    
    # File created check (anti-gaming)
    task_start = result_data.get("task_start", 0)
    file_mtime = result_data.get("file_mtime", 0)
    if file_mtime > task_start:
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp invalid (old file?).")

    # Geometry Checks
    if geometry.get("valid_solid"):
        score += 15
        feedback.append("Valid 3D solid found.")
        
        # Bounding Box (Approx 120 x 40 x 10)
        # Tolerance: Length 115-125, Width 38-42, Height 9-11
        bbox = geometry.get("bbox", [0, 0, 0])
        # Sort dims to be robust against orientation changes, though Z is usually thickness
        dims = sorted(bbox)
        # Expecting approx [10, 40, 120]
        
        if 115 <= dims[2] <= 125:
            score += 10
            feedback.append(f"Length correct ({dims[2]:.1f}mm).")
        else:
            feedback.append(f"Length incorrect ({dims[2]:.1f}mm).")
            
        if 38 <= dims[1] <= 42:
            score += 10
            feedback.append(f"Width correct ({dims[1]:.1f}mm).")
        
        if 9 <= dims[0] <= 11:
            score += 10
            feedback.append(f"Thickness correct ({dims[0]:.1f}mm).")
            
        # Holes
        if geometry.get("has_big_hole"):
            score += 15
            feedback.append("Big end hole (Ø30) found.")
        else:
            feedback.append("Big end hole missing.")
            
        if geometry.get("has_small_hole"):
            score += 15
            feedback.append("Small end hole (Ø12) found.")
        else:
            feedback.append("Small end hole missing.")
            
    else:
        feedback.append("No valid solid geometry found in file.")

    # 4. VLM Verification (Visual check for I-beam recess)
    # Programmatic check for recess is hard without complex BRep analysis
    # So we use VLM to verify the "I-beam" look
    
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this CAD model of a connecting rod.
        1. Does it look like a mechanical connecting rod (two round ends connected by a shaft)?
        2. Is there a visible recessed 'pocket' or indentation on the straight shaft section (making it look like an I-beam or H-beam profile)?
        
        Reply JSON: {"is_rod": bool, "has_recess": bool}
        """
        try:
            vlm_out = query_vlm(images=[final_screenshot], prompt=prompt).get("parsed", {})
            if vlm_out.get("is_rod"):
                vlm_score += 5
            if vlm_out.get("has_recess"):
                vlm_score += 10
                feedback.append("I-beam recess visible.")
            else:
                feedback.append("Recess not clearly visible.")
        except Exception:
            feedback.append("VLM verification failed.")
            
    score += vlm_score

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }