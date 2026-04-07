#!/usr/bin/env python3
"""
Verifier for animate_bouncing_ball task.

Criteria:
1. Output Existence (24+ frames)
2. Content Creation (Files created during task)
3. Object Detection (Red ball present)
4. Trajectory Verification (High -> Low -> High)
5. Background Presence (Not blank/transparent)
"""

import json
import os
import tempfile
import logging
import numpy as np
import cv2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_red_centroid(image_path):
    """
    Detects the largest red object in the image.
    Returns (x, y) centroid or None.
    """
    try:
        # Load image with OpenCV
        img = cv2.imread(image_path)
        if img is None:
            return None
        
        # Convert to HSV for better color segmentation
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        
        # Define Red color range (Red wraps around 180)
        # Lower red mask (0-10)
        lower_red1 = np.array([0, 100, 100])
        upper_red1 = np.array([10, 255, 255])
        
        # Upper red mask (170-180)
        lower_red2 = np.array([170, 100, 100])
        upper_red2 = np.array([180, 255, 255])
        
        mask1 = cv2.inRange(hsv, lower_red1, upper_red1)
        mask2 = cv2.inRange(hsv, lower_red2, upper_red2)
        mask = mask1 + mask2
        
        # Find contours
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            return None
            
        # Get largest contour
        c = max(contours, key=cv2.contourArea)
        
        # Ignore very small noise
        if cv2.contourArea(c) < 50:
            return None
            
        M = cv2.moments(c)
        if M["m00"] != 0:
            cx = int(M["m10"] / M["m00"])
            cy = int(M["m01"] / M["m00"])
            return (cx, cy)
        return None
    except Exception as e:
        logger.error(f"Error processing {image_path}: {e}")
        return None

def check_background(image_path):
    """
    Checks if the image has content other than the ball (i.e., the background).
    Returns True if background seems present.
    """
    try:
        img = cv2.imread(image_path)
        if img is None: 
            return False
            
        # Sample pixels from top-left corner (wall) and bottom-left (floor)
        # Setup creates wall at (220, 220, 230) and floor at (100, 80, 60)
        
        # Check Wall Area (y=50, x=50)
        pixel_wall = img[50, 50] # BGR
        # Check Floor Area (y=1000, x=50)
        pixel_floor = img[1000, 50]
        
        # Check for pure white/black/transparent (assuming default background is white/transparent)
        is_not_empty = np.mean(img) > 10 and np.mean(img) < 250
        
        # Check if pixels resemble our generated background
        # Wall roughly BGR(230, 220, 220)
        wall_match = np.all(pixel_wall > 150) # Light color
        
        return is_not_empty and wall_match
    except Exception as e:
        return False

def verify_animate_bouncing_ball(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Score: File Count (20 pts)
    file_count = result.get('file_count', 0)
    if file_count >= 24:
        score += 20
        feedback_parts.append(f"Frame count OK ({file_count})")
    elif file_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient frames ({file_count}/24)")
    else:
        feedback_parts.append("No frames rendered")
        return {"passed": False, "score": 0, "feedback": "No output frames found"}

    # 3. Score: Timestamp Check (10 pts)
    new_files = result.get('files_newer_than_start', 0)
    if new_files >= 24:
        score += 10
        feedback_parts.append("Files created during task")
    elif new_files > 0:
        score += 5
        feedback_parts.append("Some files created during task")
    else:
        feedback_parts.append("Files are old (pre-existing?)")
        
    # 4. Image Analysis (Total 70 pts)
    # We need to copy the images out to analyze them
    temp_f1 = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    temp_f12 = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    temp_f24 = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    
    images_available = False
    
    try:
        # Try copying from /tmp inside container where export_result put them
        copy_from_env("/tmp/frame_1.png", temp_f1)
        copy_from_env("/tmp/frame_12.png", temp_f12)
        copy_from_env("/tmp/frame_24.png", temp_f24)
        images_available = True
    except Exception as e:
        feedback_parts.append(f"Failed to retrieve key frames for analysis: {e}")
        
    if images_available:
        # Check Background (10 pts)
        if check_background(temp_f1):
            score += 10
            feedback_parts.append("Background visible")
        else:
            feedback_parts.append("Background missing or solid color")
            
        # Detect Ball (20 pts)
        c1 = get_red_centroid(temp_f1)
        c12 = get_red_centroid(temp_f12)
        c24 = get_red_centroid(temp_f24)
        
        if c1 and c12 and c24:
            score += 20
            feedback_parts.append("Red ball detected in all key frames")
            
            # Trajectory Analysis (40 pts)
            y1 = c1[1]
            y12 = c12[1]
            y24 = c24[1]
            
            # Assuming 1080p, y=0 is top, y=1080 is bottom
            # Floor is around y=864
            
            # Check 1: Impact is lower than Start (Gravity)
            if y12 > y1 + 100: # Significant drop
                score += 15
                feedback_parts.append("Motion: Fall detected")
            else:
                feedback_parts.append(f"Motion: No fall detected (Y1={y1}, Y12={y12})")
                
            # Check 2: Impact is lower than End (Bounce)
            if y12 > y24 + 100: # Significant rise
                score += 15
                feedback_parts.append("Motion: Bounce detected")
            else:
                feedback_parts.append(f"Motion: No bounce detected (Y12={y12}, Y24={y24})")
                
            # Check 3: Impact is near floor (Accuracy)
            if y12 > 700: # Roughly bottom 3rd
                score += 10
                feedback_parts.append("Motion: Hit floor")
            else:
                feedback_parts.append(f"Motion: Did not hit floor (Impact Y={y12})")
                
        else:
            feedback_parts.append("Red ball not detected in one or more key frames")
            
    # Cleanup
    for f in [temp_f1, temp_f12, temp_f24]:
        if os.path.exists(f):
            try:
                os.unlink(f)
            except:
                pass

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }