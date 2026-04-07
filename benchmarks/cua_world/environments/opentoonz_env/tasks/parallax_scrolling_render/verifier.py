#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import math

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_centroid_x(image_path, target_color_rgb):
    """
    Calculates the X-coordinate of the centroid of pixels matching a target color.
    """
    try:
        from PIL import Image
        img = Image.open(image_path).convert("RGB")
        width, height = img.size
        pixels = img.load()
        
        target_r, target_g, target_b = target_color_rgb
        
        sum_x = 0
        count = 0
        
        # Simple color thresholding (exact match or close to it)
        # Using a tolerance since rendering might compress/alter colors slightly
        tolerance = 30
        
        for y in range(height):
            for x in range(width):
                r, g, b = pixels[x, y]
                
                # Check distance to target color
                dist = math.sqrt((r - target_r)**2 + (g - target_g)**2 + (b - target_b)**2)
                
                if dist < tolerance:
                    sum_x += x
                    count += 1
        
        if count == 0:
            return None
        
        return sum_x / count
    except Exception as e:
        logger.error(f"Error analyzing image {image_path}: {e}")
        return None

def verify_parallax_scrolling_render(traj, env_info, task_info):
    """
    Verifies the parallax scrolling task.
    
    Criteria:
    1. Output files exist and count >= 24.
    2. Files created during task.
    3. Motion analysis:
       - Foreground (Green) moves distance D_fg
       - Background (Red) moves distance D_bg
       - D_fg > 2 * D_bg
       - D_bg > 10 pixels (must move)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_frame_count = metadata.get('min_frame_count', 24)
    target_ratio = metadata.get('parallax_ratio', 2.0)
    min_bg_movement = metadata.get('min_bg_movement', 10)

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    frame_count = result.get("frame_count", 0)
    files_new = result.get("files_created_during_task", False)
    first_path = result.get("first_frame_path", "")
    last_path = result.get("last_frame_path", "")

    score = 0
    feedback = []

    # Criterion 1: Frame Count (15 pts)
    if frame_count >= min_frame_count:
        score += 15
        feedback.append(f"Frame count OK ({frame_count})")
    else:
        feedback.append(f"Insufficient frames ({frame_count}/{min_frame_count})")

    # Criterion 2: Timestamp (10 pts)
    if files_new:
        score += 10
        feedback.append("Files created during task")
    else:
        feedback.append("Files are old or pre-existing")

    # Criterion 3: Motion Analysis (75 pts)
    if not first_path or not last_path:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback) + " | Missing output frames"}

    # Copy images for analysis
    temp_first = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    temp_last = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        copy_from_env(first_path, temp_first.name)
        copy_from_env(last_path, temp_last.name)
        
        # Analyze Green (Foreground) - RGB (0, 255, 0)
        fg_start_x = get_centroid_x(temp_first.name, (0, 255, 0))
        fg_end_x = get_centroid_x(temp_last.name, (0, 255, 0))
        
        # Analyze Red (Background) - RGB (255, 0, 0)
        bg_start_x = get_centroid_x(temp_first.name, (255, 0, 0))
        bg_end_x = get_centroid_x(temp_last.name, (255, 0, 0))
        
        if None in [fg_start_x, fg_end_x, bg_start_x, bg_end_x]:
            feedback.append("Could not detect Red and Green objects in frames")
        else:
            # Calculate displacements (absolute)
            disp_fg = abs(fg_end_x - fg_start_x)
            disp_bg = abs(bg_end_x - bg_start_x)
            
            feedback.append(f"FG Move: {disp_fg:.1f}px, BG Move: {disp_bg:.1f}px")
            
            # Check BG movement (15 pts)
            if disp_bg >= min_bg_movement:
                score += 15
                feedback.append("Background moved successfully")
            else:
                feedback.append("Background is static or moved too little")
                
            # Check Objects Visible (20 pts)
            # Implied if we calculated centroids, but let's be explicit
            score += 20
            
            # Check Parallax Ratio (40 pts)
            # Avoid division by zero
            if disp_bg > 0:
                ratio = disp_fg / disp_bg
                feedback.append(f"Parallax Ratio: {ratio:.2f}")
                
                if ratio >= target_ratio:
                    score += 40
                    feedback.append("Parallax effect achieved (FG faster than BG)")
                else:
                    feedback.append(f"Parallax insufficient (Target > {target_ratio})")
            else:
                feedback.append("Cannot calculate ratio (BG static)")

    except Exception as e:
        feedback.append(f"Image analysis failed: {e}")
    finally:
        if os.path.exists(temp_first.name):
            os.unlink(temp_first.name)
        if os.path.exists(temp_last.name):
            os.unlink(temp_last.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }