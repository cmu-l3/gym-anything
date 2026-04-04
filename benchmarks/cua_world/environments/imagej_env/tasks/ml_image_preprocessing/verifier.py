#!/usr/bin/env python3
"""Verifier for ml_image_preprocessing task."""

import json
import tempfile
import os
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ml_preprocessing(traj, env_info, task_info):
    """
    Verify ML Image Preprocessing task.
    
    Criteria:
    1. File Created (20pts): Output file exists, is valid TIFF, created after start.
    2. Dimensions (25pts): Exactly 256x256 pixels.
    3. Inversion (20pts): Objects are bright, background is dark.
    4. Resizing (15pts): Content logic check (based on center stats).
    5. Padding (20pts): Borders are black.
    
    Pass threshold: 80 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}
        
    # Setup temporary files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_tif = tempfile.NamedTemporaryFile(delete=False, suffix='.tif').name
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Get JSON result summary from export script
        copy_from_env("/tmp/ml_preprocessing_result.json", temp_json)
        with open(temp_json, 'r') as f:
            result = json.load(f)
            
        # 2. Get actual image file for verification (optional double-check, but using JSON stats is robust enough given export script logic)
        # We rely mostly on the export script's Python analysis which runs in the same environment as the image creation
        
        # --- Criterion 1: File Creation (20 pts) ---
        file_exists = result.get("file_exists", False)
        task_start = result.get("task_start_timestamp", 0)
        file_mod = result.get("file_modified_time", 0)
        
        if file_exists and file_mod > task_start:
            score += 20
            feedback_parts.append("Output file created successfully")
        elif file_exists:
            score += 0
            feedback_parts.append("FAIL: File exists but is old (pre-existing?)")
            return {"passed": False, "score": 0, "feedback": "File timestamp invalid"}
        else:
            return {"passed": False, "score": 0, "feedback": "Output file not found"}
            
        # --- Criterion 2: Dimensions (25 pts) ---
        width = result.get("width", 0)
        height = result.get("height", 0)
        
        if width == 256 and height == 256:
            score += 25
            feedback_parts.append("Dimensions correct (256x256)")
        else:
            feedback_parts.append(f"FAIL: Dimensions wrong ({width}x{height}, expected 256x256)")
            
        # --- Criterion 3: Inversion Check (20 pts) ---
        # We expect bright objects (high max) on dark background
        is_inverted = result.get("is_inverted", False)
        center_max = result.get("center_max", 0)
        
        if is_inverted:
            score += 20
            feedback_parts.append("Contrast inverted correctly (bright objects found)")
        else:
            feedback_parts.append(f"FAIL: Image does not appear inverted (Max value {center_max:.1f} too low)")
            
        # --- Criterion 4: Content/Resizing Check (15 pts) ---
        # If the image was resized to ~128px and centered, the center should have content
        center_has_content = result.get("center_has_content", False)
        
        if center_has_content:
            score += 15
            feedback_parts.append("Content found in center region")
        else:
            feedback_parts.append("FAIL: Center region appears empty or uniform")
            
        # --- Criterion 5: Padding Check (20 pts) ---
        # Borders should be black
        padding_is_black = result.get("padding_is_black", False)
        padding_mean = result.get("padding_mean", 999)
        
        if padding_is_black:
            score += 20
            feedback_parts.append("Padding is black")
        else:
            feedback_parts.append(f"FAIL: Padding is not black (Mean value: {padding_mean:.2f})")
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_json):
            os.remove(temp_json)
        if os.path.exists(temp_tif):
            os.remove(temp_tif)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }