#!/usr/bin/env python3
"""
Verifier for Frame-by-Frame Tutorial Analysis task

Uses computer vision to detect red square marker in snapshot.
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment,
    CV2_AVAILABLE,
    PIL_AVAILABLE
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import cv2 and numpy
if CV2_AVAILABLE:
    import cv2
    import numpy as np


def detect_red_marker(image_path):
    """
    Detect red square marker in image using computer vision.
    
    Returns:
        tuple: (success, feedback_dict) where feedback_dict contains detection details
    """
    if not CV2_AVAILABLE:
        logger.warning("OpenCV not available, using basic image verification")
        return False, {"error": "OpenCV not available for marker detection"}
    
    try:
        # Read image
        img = cv2.imread(image_path)
        if img is None:
            return False, {"error": "Cannot read image file"}
        
        h, w = img.shape[:2]
        center_x, center_y = w // 2, h // 2
        
        logger.info(f"Image dimensions: {w}x{h}")
        
        # Convert BGR to HSV for better red detection
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        
        # Define red color range in HSV
        # Red wraps around in HSV (0-10 and 170-180)
        lower_red1 = np.array([0, 100, 100])
        upper_red1 = np.array([10, 255, 255])
        lower_red2 = np.array([170, 100, 100])
        upper_red2 = np.array([180, 255, 255])
        
        # Create masks for red color
        mask1 = cv2.inRange(hsv, lower_red1, upper_red1)
        mask2 = cv2.inRange(hsv, lower_red2, upper_red2)
        red_mask = cv2.bitwise_or(mask1, mask2)
        
        # Find contours in the red mask
        contours, _ = cv2.findContours(red_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            return False, {
                "error": "No red regions detected",
                "red_pixels": int(np.sum(red_mask > 0)),
                "total_pixels": h * w
            }
        
        logger.info(f"Found {len(contours)} red contours")
        
        # Find largest contour (should be our marker)
        largest_contour = max(contours, key=cv2.contourArea)
        area = cv2.contourArea(largest_contour)
        
        logger.info(f"Largest contour area: {area} sq pixels")
        
        # Check if area is reasonable for 100x100px marker (6400-14400 sq pixels with tolerance)
        if area < 5000:
            return False, {
                "error": f"Marker too small: {area:.0f} sq pixels (expected ~10000)",
                "area": area
            }
        
        if area > 20000:
            return False, {
                "error": f"Marker too large: {area:.0f} sq pixels (expected ~10000)",
                "area": area
            }
        
        # Get bounding box of the marker
        x, y, box_w, box_h = cv2.boundingRect(largest_contour)
        marker_center_x = x + box_w // 2
        marker_center_y = y + box_h // 2
        
        logger.info(f"Marker bounding box: {box_w}x{box_h} at ({x}, {y})")
        logger.info(f"Marker center: ({marker_center_x}, {marker_center_y})")
        logger.info(f"Frame center: ({center_x}, {center_y})")
        
        # Check if marker is centered (within 20% tolerance)
        tolerance_x = w * 0.20
        tolerance_y = h * 0.20
        
        offset_x = abs(marker_center_x - center_x)
        offset_y = abs(marker_center_y - center_y)
        
        is_centered_x = offset_x <= tolerance_x
        is_centered_y = offset_y <= tolerance_y
        
        if not is_centered_x:
            return False, {
                "error": f"Marker not horizontally centered: {offset_x:.0f}px off (tolerance: {tolerance_x:.0f}px)",
                "offset_x": offset_x,
                "offset_y": offset_y,
                "area": area,
                "size": f"{box_w}x{box_h}"
            }
        
        if not is_centered_y:
            return False, {
                "error": f"Marker not vertically centered: {offset_y:.0f}px off (tolerance: {tolerance_y:.0f}px)",
                "offset_x": offset_x,
                "offset_y": offset_y,
                "area": area,
                "size": f"{box_w}x{box_h}"
            }
        
        # Check if marker is roughly square (aspect ratio between 0.8 and 1.2)
        aspect_ratio = box_w / box_h if box_h > 0 else 0
        
        if aspect_ratio < 0.8 or aspect_ratio > 1.2:
            return False, {
                "error": f"Marker not square: aspect ratio {aspect_ratio:.2f}",
                "aspect_ratio": aspect_ratio,
                "size": f"{box_w}x{box_h}",
                "area": area
            }
        
        # All checks passed!
        return True, {
            "success": True,
            "marker_size": f"{box_w}x{box_h}",
            "marker_center": f"({marker_center_x}, {marker_center_y})",
            "frame_center": f"({center_x}, {center_y})",
            "offset": f"({offset_x:.0f}, {offset_y:.0f})",
            "area": area,
            "aspect_ratio": f"{aspect_ratio:.2f}"
        }
        
    except Exception as e:
        logger.error(f"Error in marker detection: {e}", exc_info=True)
        return False, {"error": f"Detection error: {str(e)}"}


def verify_frame_step_analysis(traj, env_info, task_info):
    """
    Verify frame-by-frame analysis task completion.
    
    Checks:
    1. Snapshot file exists and is valid
    2. Red marker is detected in snapshot
    3. Marker is properly centered
    4. Marker has correct size and shape
    5. Image quality is good
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Check if snapshot exists
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_frame_step_snapshot.png",
        file_type='image'
    )
    
    if not success:
        # Check if no-snapshot marker exists
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_frame_step_no_snapshot.txt", temp_marker.name)
            os.unlink(temp_marker.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "No snapshot captured - agent did not take a snapshot"
            }
        except:
            pass
        
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Snapshot not found: {error}"
        }
    
    # Criterion 1: Snapshot exists
    criteria_met += 1
    feedback_parts.append("✅ Snapshot captured")
    
    image_data = file_info.get('data', {})
    image_path = file_info.get('filepath', '')
    
    # Criterion 2: Image has reasonable quality (file size)
    size_kb = image_data.get('size_kb', 0)
    if size_kb > 50:
        criteria_met += 1
        feedback_parts.append(f"✅ Image quality OK ({size_kb:.1f} KB)")
    elif size_kb > 10:
        criteria_met += 0.5
        feedback_parts.append(f"⚠️ Image quality marginal ({size_kb:.1f} KB)")
    else:
        feedback_parts.append(f"❌ Image quality poor ({size_kb:.1f} KB)")
    
    # Main criteria: Detect red marker
    if CV2_AVAILABLE:
        marker_found, detection_info = detect_red_marker(image_path)
        
        if marker_found:
            # Criterion 3, 4, 5: Marker detected, centered, and proper size
            criteria_met += 3  # All remaining criteria met
            
            feedback_parts.append(f"✅ Red marker detected: {detection_info.get('marker_size')}")
            feedback_parts.append(f"✅ Marker centered: offset {detection_info.get('offset')}")
            feedback_parts.append(f"✅ Marker shape valid: AR={detection_info.get('aspect_ratio')}")
        else:
            # Marker not found - provide detailed feedback
            error_msg = detection_info.get('error', 'Unknown error')
            feedback_parts.append(f"❌ Marker detection failed: {error_msg}")
            
            # Give partial credit based on what was detected
            if 'area' in detection_info:
                # Something red was detected, just not quite right
                criteria_met += 1
                feedback_parts.append(f"⚠️ Red region found but incorrect (area: {detection_info.get('area', 0):.0f})")
    else:
        # OpenCV not available - can only do basic checks
        feedback_parts.append("⚠️ Computer vision not available - cannot verify marker")
        logger.warning("OpenCV not available for marker verification")
        
        # Give some credit for having a snapshot
        if size_kb > 100:
            criteria_met += 1.5
            feedback_parts.append("⚠️ Basic validation passed (OpenCV unavailable)")
    
    # Cleanup
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker
    temp_completion = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_frame_step_completed.txt", temp_completion.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_completion.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }