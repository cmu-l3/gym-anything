#!/usr/bin/env python3
"""
Verifier for convert_vector_to_raster task in gvSIG Desktop.

Verification Strategy:
1. Check if output TIFF file exists and was created during the task.
2. Validate TIFF format and dimensions (approx 360x180 for 1.0 degree global grid).
3. Validate content: ensure it's not a solid color (should have multiple values from MAPCOLOR7).
4. VLM Verification: Check trajectory for tool usage.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_vector_to_raster(traj, env_info, task_info):
    """
    Verify the vector to raster conversion task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width_approx', 360)
    expected_height = metadata.get('expected_height_approx', 180)
    
    # Allow some tolerance in dimensions (bounding box calculations can vary slightly)
    dim_tolerance = 20 

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
    
    # ----------------------------------------------------------------
    # Programmatic Verification (60 points)
    # ----------------------------------------------------------------
    
    # Criterion 1: File Exists & Created During Task (20 pts)
    file_exists = result.get('file_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if file_exists:
        if created_during:
            score += 20
            feedback_parts.append("Output file created successfully.")
        else:
            score += 5
            feedback_parts.append("Output file exists but has old timestamp (not created in this session).")
    else:
        feedback_parts.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Valid TIFF & Dimensions (20 pts)
    is_valid = result.get('is_valid_tiff', False)
    width = result.get('image_width', 0)
    height = result.get('image_height', 0)
    
    dims_ok = False
    if is_valid:
        if (abs(width - expected_width) <= dim_tolerance) and (abs(height - expected_height) <= dim_tolerance):
            score += 20
            dims_ok = True
            feedback_parts.append(f"Dimensions correct ({width}x{height}).")
        else:
            score += 5
            feedback_parts.append(f"Dimensions incorrect (Expected ~{expected_width}x{expected_height}, got {width}x{height}).")
    else:
        feedback_parts.append("File is not a valid TIFF image.")

    # Criterion 3: Content Check (20 pts)
    # We expect MAPCOLOR7 values (1-7), so there should be multiple unique values
    unique_vals = result.get('unique_values_count', 0)
    
    if unique_vals >= 4: # At least a few different colors
        score += 20
        feedback_parts.append("Raster content valid (multiple data values detected).")
    elif unique_vals > 1:
        score += 10
        feedback_parts.append("Raster content suspicious (very few unique values).")
    else:
        feedback_parts.append("Raster appears empty or solid color.")

    # ----------------------------------------------------------------
    # VLM Verification (40 points)
    # ----------------------------------------------------------------
    
    # We check if the agent actually used the Geoprocessing tools
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = (
            "Review these screenshots of a gvSIG Desktop session. "
            "The user task was to convert a vector layer to raster using Geoprocessing tools. "
            "Look for evidence of:\n"
            "1. The Geoprocessing Toolbox or SEXTANTE toolbox being open.\n"
            "2. A dialog titled 'Rasterize', 'Vector to Grid', or similar.\n"
            "3. Parameters being set (Cell size 1.0, Field MAPCOLOR7).\n"
            "4. A progress bar or the final map changing appearance.\n"
            "Do you see evidence that the agent performed the rasterization process?"
        )
        
        vlm_response = query_vlm(
            images=frames + [final_shot], 
            prompt=vlm_prompt,
            format_response=True
        )
        
        if vlm_response.get("answer_bool", False):
            score += 40
            feedback_parts.append("VLM confirms workflow.")
        else:
            feedback_parts.append("VLM did not observe clear Geoprocessing workflow.")
            # Fallback: if programmatic check was perfect, give partial credit for VLM to avoid false negatives
            if dims_ok and unique_vals >= 4:
                score += 20 

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passing_score = 75
    passed = score >= passing_score

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }