#!/usr/bin/env python3
"""
Verifier for apply_pseudocolor_to_raster task.

Verifies that:
1. The agent exported a PNG file.
2. The PNG file contains a colorful image (pseudocolor applied), not grayscale.
3. The file was created during the task window.
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apply_pseudocolor_to_raster(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Output file exists (20 pts)
    output_exists = result.get('output_exists', False)
    if output_exists:
        score += 20
        feedback_parts.append("Output file exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: File created during task (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this session.")

    # Criterion 3: Image Color Analysis (50 pts)
    # Check if the image is grayscale or colorful
    is_colorful = False
    color_score = 0
    
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(result.get('output_path'), temp_img.name)
        
        with Image.open(temp_img.name) as img:
            img_rgb = img.convert('RGB')
            arr = np.array(img_rgb)
            
            # Calculate difference between channels
            # Grayscale images have R ~= G ~= B
            # Colorful images (pseudocolor) have significant differences
            
            # diff_rg = |R - G|
            diff_rg = np.abs(arr[:,:,0].astype(int) - arr[:,:,1].astype(int))
            # diff_gb = |G - B|
            diff_gb = np.abs(arr[:,:,1].astype(int) - arr[:,:,2].astype(int))
            
            mean_diff = np.mean(diff_rg) + np.mean(diff_gb)
            
            # Threshold: A pure grayscale image has mean_diff = 0
            # A compressed JPEG grayscale might have small noise (< 2.0)
            # A pseudocolor ramp (rainbow) will have high diff (> 20.0 usually)
            
            logger.info(f"Image Color Analysis: Mean Channel Diff = {mean_diff:.2f}")
            
            if mean_diff > 10.0:
                is_colorful = True
                color_score = 50
                feedback_parts.append(f"Image has color (Color variance score: {mean_diff:.1f}).")
            elif mean_diff > 2.0:
                is_colorful = True
                color_score = 25
                feedback_parts.append(f"Image has slight color, possibly weak ramp (Color variance score: {mean_diff:.1f}).")
            else:
                feedback_parts.append(f"Image appears to be grayscale (Color variance score: {mean_diff:.1f}). Did you apply the color table?")
                
    except Exception as e:
        feedback_parts.append(f"Failed to analyze image: {str(e)}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)
            
    score += color_score

    # Criterion 4: App was running (20 pts)
    if result.get('app_was_running', False):
        score += 20
    else:
        feedback_parts.append("gvSIG was not running at the end of the task.")

    # Final Pass/Fail
    passed = (score >= 70) and is_colorful
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }