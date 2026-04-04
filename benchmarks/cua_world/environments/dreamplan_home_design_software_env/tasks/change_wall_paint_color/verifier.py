#!/usr/bin/env python3
"""
Verifier for change_wall_paint_color task.

Verification Strategy:
1. Check if the user saved the project file (RedLivingRoom.ndp).
2. Check if the user saved a screenshot (red_walls_preview.png).
3. Verify the screenshot actually contains a significant amount of red/burgundy pixels.
4. Use VLM trajectory analysis to confirm the workflow (wall selection, color picker usage).
"""

import json
import os
import tempfile
import logging
import cv2
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not found, falling back to programmatic verification only")


def is_color_red(h, s, v):
    """
    Check if HSV values correspond to a deep red/burgundy color.
    OpenCV Hue range is [0, 179]. Red wraps around 0/180.
    Deep Red/Burgundy: High Saturation, Moderate-Low Value (but not black).
    """
    # Red is typically 0-10 or 170-180 in OpenCV Hue
    is_red_hue = (h <= 10) or (h >= 170)
    
    # We want visible color, so decent saturation
    is_saturated = s > 50 
    
    # Not too dark (black) and not too bright (bright red/pink), deep red implies somewhat lower value but visible
    # Actually, allow bright red too, just check it's red.
    has_value = v > 40
    
    return is_red_hue and is_saturated and has_value


def analyze_screenshot_color(image_path):
    """
    Analyze the image to see if it contains significant red/burgundy pixels.
    Returns a score (0-100) based on red content presence.
    """
    if not os.path.exists(image_path):
        return 0, "Screenshot file not found"
        
    try:
        img = cv2.imread(image_path)
        if img is None:
            return 0, "Failed to load image"

        # Convert to HSV
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        
        # Define ranges for Red (two ranges because red wraps around 0)
        # Range 1: 0-10
        lower_red1 = np.array([0, 50, 40])
        upper_red1 = np.array([10, 255, 255])
        
        # Range 2: 170-180
        lower_red2 = np.array([170, 50, 40])
        upper_red2 = np.array([180, 255, 255])
        
        mask1 = cv2.inRange(hsv, lower_red1, upper_red1)
        mask2 = cv2.inRange(hsv, lower_red2, upper_red2)
        mask = mask1 + mask2
        
        # Calculate percentage of red pixels
        total_pixels = img.shape[0] * img.shape[1]
        red_pixels = cv2.countNonZero(mask)
        
        red_ratio = red_pixels / total_pixels
        
        # Heuristic: Walls usually take up a significant portion of a room view (e.g. > 5-10%)
        # If the screenshot is well framed, we expect > 5% red.
        logger.info(f"Red pixel ratio: {red_ratio:.4f}")
        
        if red_ratio > 0.05:
            return 100, f"Significant red color detected ({red_ratio*100:.1f}% of image)"
        elif red_ratio > 0.01:
            return 50, f"Some red color detected ({red_ratio*100:.1f}% of image) - might be partial or distant"
        else:
            return 0, f"No significant red color detected ({red_ratio*100:.1f}%)"
            
    except Exception as e:
        logger.error(f"Error analyzing image: {e}")
        return 0, f"Error analyzing image: {e}"


def verify_change_wall_paint_color(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get JSON Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Check File Existence (Programmatic)
    if result.get('project_exists') and result.get('project_created_during_task'):
        score += 20
        feedback_parts.append("Project file saved correctly.")
    elif result.get('project_exists'):
        score += 10
        feedback_parts.append("Project file exists but timestamp check failed.")
    else:
        feedback_parts.append("Project file not saved.")

    screenshot_path_internal = result.get('internal_screenshot_path')
    screenshot_score = 0
    
    if result.get('screenshot_exists'):
        score += 10
        feedback_parts.append("Preview screenshot saved.")
        
        # 3. Analyze Screenshot Content (Programmatic)
        if screenshot_path_internal:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(screenshot_path_internal, temp_img.name)
                color_score, color_feedback = analyze_screenshot_color(temp_img.name)
                
                # Weighted score for color accuracy
                weighted_color_score = (color_score / 100) * 30  # Max 30 points for correct color
                score += weighted_color_score
                feedback_parts.append(color_feedback)
                
                if color_score > 50:
                    screenshot_score = 100 # Mark verification successful for VLM fallback logic
            except Exception as e:
                feedback_parts.append(f"Could not analyze screenshot: {e}")
            finally:
                if os.path.exists(temp_img.name):
                    os.unlink(temp_img.name)
    else:
        feedback_parts.append("Preview screenshot not found.")

    # 4. VLM Verification (Trajectory)
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = """
        Analyze these screenshots of a user using DreamPlan Home Design Software.
        The user goal is to change the living room walls to a red/burgundy color.
        
        Look for:
        1. A floor plan or 3D view of a house.
        2. Selection of wall elements.
        3. Opening a color/material picker dialog.
        4. Selecting a red or burgundy color.
        5. The final result showing red walls in the room.
        
        Return JSON:
        {
            "walls_selected": true/false,
            "color_picker_opened": true/false,
            "red_color_chosen": true/false,
            "final_result_visible": true/false,
            "final_wall_color": "description of color seen"
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('walls_selected'): vlm_score += 10
            if parsed.get('color_picker_opened'): vlm_score += 10
            if parsed.get('red_color_chosen'): vlm_score += 10
            if parsed.get('final_result_visible'): vlm_score += 10
            
            feedback_parts.append(f"VLM Analysis: {parsed.get('final_wall_color', 'unknown')}")
        except Exception as e:
            logger.error(f"VLM failed: {e}")
            # Fallback: if programmatic screenshot analysis passed, give partial VLM credit
            if screenshot_score > 50:
                vlm_score += 20
    else:
        # No VLM available, re-weight based on programmatic only
        # If programmatic color check passed, assume visual steps were likely taken
        if screenshot_score > 50:
            vlm_score = 40
            feedback_parts.append("VLM unavailable, trusting file analysis.")

    score += vlm_score

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }