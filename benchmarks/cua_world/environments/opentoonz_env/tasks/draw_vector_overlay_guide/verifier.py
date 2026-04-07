#!/usr/bin/env python3
"""
Verifier for draw_vector_overlay_guide task.

Checks:
1. Rendered PNG output exists.
2. A new Vector Level (.pli) file was created (proof of correct level type).
3. The rendered image contains a red circle overlay (Computer Vision).
"""

import json
import os
import tempfile
import cv2
import numpy as np
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_draw_vector_overlay_guide(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Output File Existence (15 pts)
    output_exists = result.get("output_exists", False)
    output_path = result.get("output_path", "")
    
    if output_exists and output_path:
        score += 15
        feedback_parts.append("Rendered output file found.")
    else:
        feedback_parts.append("No rendered output file found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Vector Level Creation (.pli file) (25 pts)
    # This proves the agent used a Toonz Vector Level, not a Raster/ToonzRaster level
    vector_exists = result.get("new_vector_level_exists", False)
    if vector_exists:
        score += 25
        feedback_parts.append("New Vector Level (.pli) created.")
    else:
        feedback_parts.append("No new Vector Level (.pli) file detected. Did you create the correct level type?")

    # 3. Image Analysis: Red Color & Circle Shape (60 pts)
    # Copy image from env
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    image_loaded = False
    try:
        copy_from_env(output_path, temp_img.name)
        img = cv2.imread(temp_img.name)
        if img is not None:
            image_loaded = True
        else:
            feedback_parts.append("Failed to read rendered image.")
    except Exception as e:
        feedback_parts.append(f"Failed to copy rendered image: {e}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    if image_loaded:
        # Convert to HSV
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        
        # Define Red ranges (Red wraps around 0/180)
        # Lower red: 0-10
        lower_red1 = np.array([0, 100, 100])
        upper_red1 = np.array([10, 255, 255])
        # Upper red: 170-180
        lower_red2 = np.array([170, 100, 100])
        upper_red2 = np.array([180, 255, 255])
        
        mask1 = cv2.inRange(hsv, lower_red1, upper_red1)
        mask2 = cv2.inRange(hsv, lower_red2, upper_red2)
        red_mask = mask1 + mask2
        
        red_pixel_count = cv2.countNonZero(red_mask)
        logger.info(f"Red pixel count: {red_pixel_count}")
        
        # Criterion 3a: Red Color Detected (25 pts)
        if red_pixel_count > 200: # Threshold for a visible line drawing
            score += 25
            feedback_parts.append("Red color detected in output.")
            
            # Criterion 3b: Circular Shape (25 pts)
            # Find contours on the red mask
            contours, _ = cv2.findContours(red_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            
            shape_detected = False
            for cnt in contours:
                if cv2.contourArea(cnt) < 50: # Ignore noise
                    continue
                    
                # Fit ellipse/circle
                if len(cnt) >= 5:
                    (x,y), (MA,ma), angle = cv2.fitEllipse(cnt)
                    # Check aspect ratio for circle-ish shape (0.5 to 2.0)
                    if ma > 0:
                        ar = MA/ma
                        if 0.6 <= ar <= 1.4: # Fairly circular
                             shape_detected = True
                             break
            
            # Hough Circle fallback
            if not shape_detected:
                # Gaussian blur to reduce noise for Hough
                blurred = cv2.GaussianBlur(red_mask, (9, 9), 2)
                circles = cv2.HoughCircles(blurred, cv2.HOUGH_GRADIENT, dp=1.2, minDist=100,
                                         param1=50, param2=30, minRadius=20, maxRadius=0)
                if circles is not None:
                    shape_detected = True

            if shape_detected:
                score += 25
                feedback_parts.append("Circular shape detected.")
            else:
                feedback_parts.append("Red pixels found, but shape is not clearly circular.")
        else:
            feedback_parts.append("No significant red color detected in output.")
            
        # Criterion 4: Content Preservation (10 pts)
        # Check if non-red parts exist (image isn't just blank or solid red)
        total_pixels = img.shape[0] * img.shape[1]
        if 0 < red_pixel_count < (total_pixels * 0.9): 
            score += 10
            feedback_parts.append("Original content visible (not obscured).")
        else:
             feedback_parts.append("Image appears empty or fully obscured.")

    passed = (score >= 60) and vector_exists # Strict on vector level usage
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }