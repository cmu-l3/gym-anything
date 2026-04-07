#!/usr/bin/env python3
"""
Verifier for create_color_index_map task.

Evaluates:
1. File existence and creation timestamp
2. Correct formatting (Valid FITS file)
3. Correct Data Type (32-bit Float to prevent negative clipping)
4. Mathematical Correctness (MAE near zero for B-V subtraction)
5. Trajectory Verification (Ensures GUI was used rather than a Python script)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_color_index_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON result exported from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (15 points)
    file_exists = result.get("file_exists", False)
    file_created = result.get("file_created_during_task", False)
    
    if file_exists and file_created:
        score += 15
        feedback_parts.append("Output file successfully created")
    elif file_exists:
        score += 5
        feedback_parts.append("Output file exists but wasn't created during this task session")
    else:
        feedback_parts.append("Output file not found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Check valid FITS format and shape (10 points)
    valid_fits = result.get("valid_fits", False)
    shape_match = result.get("shape_match", False)
    
    if valid_fits and shape_match:
        score += 10
        feedback_parts.append("Valid FITS shape and format")
    elif valid_fits:
        score += 5
        feedback_parts.append("FITS valid but shape mismatch")
    else:
        error_msg = result.get("error", "Unknown FITS error")
        feedback_parts.append(f"Invalid FITS: {error_msg}")

    # 4. Check Data Type / BITPIX (25 points)
    # FITS standard: negative BITPIX represents floating point (-32 for float32, -64 for float64)
    bitpix = result.get("bitpix", 0)
    is_float = bitpix < 0
    
    if is_float:
        score += 25
        feedback_parts.append(f"Correct data type (BITPIX={bitpix})")
    else:
        feedback_parts.append(f"Incorrect data type (BITPIX={bitpix}). Expected float (-32 or -64). Negative values may be clipped.")

    # 5. Check Mathematical Correctness (30 points)
    # We use a threshold of 0.1 to account for any tiny floating point drifts between Java and Numpy
    mae = result.get("mae", float('inf'))
    math_correct = mae < 0.1
    
    if math_correct:
        score += 30
        feedback_parts.append(f"Math accurate (MAE={mae:.5f})")
    elif mae < 100.0:
        score += 10
        feedback_parts.append(f"Math partially correct/clipped (MAE={mae:.2f})")
    else:
        feedback_parts.append(f"Math inaccurate (MAE={mae:.2f})")

    # 6. VLM Trajectory Verification - Anti-Gaming (20 points)
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)
    images = frames + [final]
    
    vlm_prompt = """
    Look at these screenshots from an AstroImageJ workflow.
    Did the user visibly open the 'Image Calculator' window (usually accessed via Process > Image Calculator) 
    and configure it to perform an image arithmetic operation?
    Answer 'Yes' if there is evidence of the Image Calculator dialog being used, otherwise 'No'.
    """
    
    try:
        vlm_response = query_vlm(images=images, prompt=vlm_prompt)
        used_gui = "yes" in vlm_response.lower()
        
        if used_gui:
            score += 20
            feedback_parts.append("VLM verified GUI calculator usage")
        else:
            feedback_parts.append("VLM did not detect Image Calculator usage (potential script bypass)")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed")

    # Determine Pass/Fail
    # To pass, they must have created the file, got the math roughly right, and used the float data type
    key_criteria_met = file_exists and valid_fits and is_float and math_correct and used_gui
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }