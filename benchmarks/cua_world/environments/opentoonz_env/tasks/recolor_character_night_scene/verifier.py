#!/usr/bin/env python3
import json
import os
import tempfile
import numpy as np
import logging
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recolor_character_night_scene(traj, env_info, task_info):
    """
    Verifies that the OpenToonz character was recolored to Night settings.
    
    Criteria:
    1. Output files exist and were created during the task.
    2. Image Analysis:
       - Presence of Target Skin Color (Dark Blue-Grey)
       - Presence of Target Shirt Color (Dark Purple)
       - Absence of Original Day Colors (Peach/Light Blue)
       - Valid Geometry (Non-empty alpha channel, not a solid square)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamps (20 points)
    score = 0
    feedback = []
    
    file_count = result_data.get("file_count", 0)
    new_files = result_data.get("files_created_during_task", 0)
    
    if file_count > 0:
        score += 10
        feedback.append(f"Found {file_count} output frames.")
    else:
        feedback.append("No output frames found.")
        return {"passed": False, "score": 0, "feedback": "No output files found."}

    if new_files >= 1:
        score += 10
        feedback.append("Files were created during the task session.")
    else:
        feedback.append("Files are old/stale. Anti-gaming check failed.")
        return {"passed": False, "score": score, "feedback": "Output files were not created during this task."}

    # 3. Image Analysis Setup
    if not result_data.get("image_available_for_analysis"):
        return {"passed": False, "score": score, "feedback": "No valid image available for analysis."}

    # Copy the analysis image out of the environment
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env(result_data["analysis_image_path"], temp_img.name)
        img = Image.open(temp_img.name).convert("RGBA")
        img_data = np.array(img)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to analyze image: {str(e)}"}
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # 4. Pixel Analysis
    
    # Target Colors from Metadata/Description
    # Skin: RGB(60, 60, 90)
    # Shirt: RGB(40, 30, 60)
    target_skin = np.array([60, 60, 90])
    target_shirt = np.array([40, 30, 60])
    tolerance = 30  # Allow some variance due to rendering/antialiasing

    # Original "Day" colors (Approximate) to ensure they are gone
    # Peach skin ~ (255, 220, 190)
    # Light Shirt ~ (200, 230, 255)
    avoid_skin = np.array([255, 220, 190])
    avoid_tolerance = 40

    # Extract RGB and Alpha
    rgb = img_data[:, :, :3]
    alpha = img_data[:, :, 3]

    # Mask for non-transparent pixels
    visible_pixels = alpha > 10
    visible_rgb = rgb[visible_pixels]
    
    if len(visible_rgb) == 0:
        return {"passed": False, "score": score, "feedback": "Rendered image is empty/transparent."}

    # Calculate distances to targets
    dist_skin = np.linalg.norm(visible_rgb - target_skin, axis=1)
    dist_shirt = np.linalg.norm(visible_rgb - target_shirt, axis=1)
    dist_avoid = np.linalg.norm(visible_rgb - avoid_skin, axis=1)

    # Count matching pixels
    skin_matches = np.sum(dist_skin < tolerance)
    shirt_matches = np.sum(dist_shirt < tolerance)
    avoid_matches = np.sum(dist_avoid < avoid_tolerance)
    total_visible = len(visible_rgb)

    # Criteria Checks

    # A. Geometry/Content Check (20 points)
    # Check if alpha channel has some variation (not just a solid block) and reasonable fill
    # A simple character render usually fills 10-50% of screen, not 100%.
    fill_ratio = total_visible / (img.width * img.height)
    
    if 0.01 < fill_ratio < 0.95:
        score += 20
        feedback.append("Geometry looks valid (reasonable content ratio).")
    else:
        feedback.append(f"Geometry suspicious (Fill ratio: {fill_ratio:.2f}). Is it blank or a solid rectangle?")

    # B. Night Skin Color Check (25 points)
    # Require at least 5% of visible pixels to match target skin
    if skin_matches / total_visible > 0.05:
        score += 25
        feedback.append("Target 'Night Skin' color detected.")
    else:
        feedback.append(f"Target 'Night Skin' color NOT detected (RGB 60,60,90). Found {skin_matches} matching pixels.")

    # C. Night Shirt Color Check (25 points)
    # Require at least 5% of visible pixels to match target shirt
    if shirt_matches / total_visible > 0.05:
        score += 25
        feedback.append("Target 'Night Shirt' color detected.")
    else:
        feedback.append(f"Target 'Night Shirt' color NOT detected (RGB 40,30,60). Found {shirt_matches} matching pixels.")

    # D. Day Colors Removed Check (10 points)
    # Fail if significant amount of original skin tone remains
    if avoid_matches / total_visible < 0.05:
        score += 10
        feedback.append("Original 'Day' colors effectively removed.")
    else:
        feedback.append("Original 'Day' colors still present! Task requires recoloring.")

    passed = score >= 65  # Threshold to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }