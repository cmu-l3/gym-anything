#!/usr/bin/env python3
"""
Verifier for cinematic_vignette_composite task.

Criteria:
1. Output files exist and are newly created.
2. Frame count >= 24.
3. Vignette Effect Verification:
   - Analyzes a sample frame.
   - Compares luminance of the center vs. corners.
   - Corners must be significantly darker than the center.
   - Center must retain visibility (not a black screen).
"""

import json
import os
import tempfile
import logging
import numpy as np
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cinematic_vignette_composite(traj, env_info, task_info):
    # 1. Setup and Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frames', 24)
    vignette_ratio_threshold = metadata.get('vignette_threshold_ratio', 0.85) # Corner brightness must be < 85% of center
    min_center_brightness = metadata.get('min_center_brightness', 20) # Center must not be black

    # Copy result.json
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 2. Check File Counts (30 points)
    new_files = result.get("new_files", 0)
    if new_files >= min_frames:
        score += 30
        feedback.append(f"Output count OK ({new_files} frames).")
    elif new_files > 0:
        score += 10
        feedback.append(f"Partial output: {new_files}/{min_frames} frames.")
    else:
        feedback.append("No output frames generated.")
        return {"passed": False, "score": 0, "feedback": "No output files found."}

    # 3. Analyze Sample Image for Vignette Effect (70 points)
    sample_path = result.get("sample_image_path")
    if not sample_path:
        feedback.append("No sample image path in result.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Copy the image from container to host
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(sample_path, temp_img.name)
        
        # Open and analyze
        with Image.open(temp_img.name) as img:
            img_gray = img.convert('L')
            width, height = img.size
            pixels = np.array(img_gray)

            # Define regions
            # Center: middle 20%
            cx, cy = width // 2, height // 2
            cw, ch = width // 5, height // 5
            center_region = pixels[cy - ch//2 : cy + ch//2, cx - cw//2 : cx + cw//2]
            
            # Corners: 10% boxes at each corner
            cw_corn, ch_corn = width // 10, height // 10
            tl = pixels[0:ch_corn, 0:cw_corn]
            tr = pixels[0:ch_corn, width-cw_corn:width]
            bl = pixels[height-ch_corn:height, 0:cw_corn]
            br = pixels[height-ch_corn:height, width-cw_corn:width]
            
            # Calculate means
            center_mean = np.mean(center_region)
            corners_mean = np.mean([np.mean(tl), np.mean(tr), np.mean(bl), np.mean(br)])

            # Analysis
            ratio = corners_mean / (center_mean + 1e-6) # Avoid div/0
            
            logger.info(f"Center Mean: {center_mean}, Corners Mean: {corners_mean}, Ratio: {ratio}")

            # Criterion 3a: Center Visibility (20 pts)
            if center_mean > min_center_brightness:
                score += 20
                feedback.append("Center brightness is good (subject visible).")
            else:
                feedback.append(f"Image is too dark (Center mean: {center_mean:.1f}).")

            # Criterion 3b: Vignette Falloff (50 pts)
            if ratio < vignette_ratio_threshold:
                score += 50
                feedback.append(f"Vignette effect detected! Corner brightness is {ratio*100:.1f}% of center.")
            else:
                feedback.append(f"No vignette detected. Corners ({corners_mean:.1f}) are similar to center ({center_mean:.1f}). Ratio: {ratio:.2f}")

    except Exception as e:
        feedback.append(f"Image analysis failed: {str(e)}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }