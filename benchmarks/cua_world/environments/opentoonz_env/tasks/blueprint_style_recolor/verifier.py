#!/usr/bin/env python3
"""
Verifier for blueprint_style_recolor task.
"""

import json
import os
import tempfile
import logging
from PIL import Image
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blueprint_style_recolor(traj, env_info, task_info):
    """
    Verify the blueprint style animation task.
    
    Criteria:
    1. Output files exist (min 12 frames).
    2. Files created during task session.
    3. Background color is Dark Blue.
    4. Line art color is Cyan.
    5. Character is visible (not just a solid color image).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    target_line = metadata.get('target_line_color', [0, 255, 255]) # Cyan
    target_bg = metadata.get('target_bg_color', [0, 0, 50])        # Dark Blue
    tolerance = metadata.get('color_tolerance', 40)
    min_frames = metadata.get('min_frame_count', 12)

    # 1. Retrieve JSON result
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Sample Image
    sample_path = task_result.get("sample_frame_path", "")
    sample_img_local = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    has_image = False
    
    if sample_path:
        try:
            copy_from_env(sample_path, sample_img_local)
            has_image = True
        except Exception:
            has_image = False

    # Scoring Setup
    score = 0
    feedback = []

    # Criterion A: Frame Count (20 pts)
    file_count = task_result.get("file_count", 0)
    if file_count >= min_frames:
        score += 20
        feedback.append(f"Generated {file_count} frames (Pass)")
    elif file_count > 0:
        score += 10
        feedback.append(f"Generated {file_count}/{min_frames} frames (Partial)")
    else:
        feedback.append("No frames generated")

    # Criterion B: Timestamp Check (10 pts)
    # Prevents using pre-rendered files
    new_files = task_result.get("files_created_during_task", 0)
    if new_files >= min_frames:
        score += 10
    elif new_files > 0:
        score += 5
        feedback.append("Some files might be stale")

    # Criterion C: Pixel Analysis (70 pts total)
    if has_image:
        try:
            img = Image.open(sample_img_local).convert("RGB")
            width, height = img.size
            pixels = np.array(img)

            # Define colors
            bg_target = np.array(target_bg)
            line_target = np.array(target_line)

            # 1. Check Background (Corners) - 25 pts
            # Sample 4 corners
            corners = [
                pixels[0, 0],
                pixels[0, width-1],
                pixels[height-1, 0],
                pixels[height-1, width-1]
            ]
            
            bg_matches = 0
            for p in corners:
                dist = np.linalg.norm(p - bg_target)
                if dist < tolerance:
                    bg_matches += 1
            
            if bg_matches >= 3:
                score += 25
                feedback.append("Background color matches Dark Blue")
            else:
                feedback.append(f"Background color incorrect. Found RGB: {corners[0]}")

            # 2. Check Line Art (Center Region) - 25 pts
            # The character is usually in the center. We look for Cyan pixels.
            # We don't check every pixel, just ensure significant cyan presence.
            
            # Crop to center 50%
            center_crop = pixels[int(height*0.25):int(height*0.75), int(width*0.25):int(width*0.75)]
            
            # Count pixels close to Cyan
            # Calculate distance of every pixel to Cyan
            diff = center_crop - line_target
            dist = np.linalg.norm(diff, axis=2)
            cyan_pixel_count = np.sum(dist < tolerance)
            
            # We expect at least some line art (e.g., > 0.5% of pixels in center)
            total_center_pixels = center_crop.shape[0] * center_crop.shape[1]
            cyan_ratio = cyan_pixel_count / total_center_pixels

            if cyan_ratio > 0.005: # Threshold determined by typical line art density
                score += 25
                feedback.append("Line art color matches Cyan")
            else:
                feedback.append(f"No Cyan line art detected (ratio: {cyan_ratio:.4f})")

            # 3. Check for Original Black Lines (Negative Check) - 10 pts
            # If the user didn't change the palette, lines will be black (0,0,0)
            black_target = np.array([0, 0, 0])
            diff_blk = center_crop - black_target
            dist_blk = np.linalg.norm(diff_blk, axis=2)
            black_pixel_count = np.sum(dist_blk < 20) # Strict tolerance for pure black
            
            # If we see lots of black, they likely didn't recolor
            if black_pixel_count < (cyan_pixel_count * 0.5): 
                # Good: substantially less black than cyan (or no black)
                score += 10
            else:
                feedback.append("Significant black pixels found (Lines likely not recolored)")

            # 4. Visibility Check (10 pts)
            # Ensure image isn't just a solid color rectangle
            std_dev = np.std(pixels)
            if std_dev > 5:
                score += 10
            else:
                feedback.append("Image appears to be a solid color (Blank)")

        except Exception as e:
            feedback.append(f"Image analysis failed: {str(e)}")
    else:
        feedback.append("Could not analyze image (No output found)")

    # Cleanup
    if os.path.exists(sample_img_local):
        os.unlink(sample_img_local)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }