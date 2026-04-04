#!/usr/bin/env python3
"""
Verifier for GIMP rectangle stroke task.
Checks if a rectangular stroke outline was added to the image.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)

# Try to import OpenCV for advanced edge detection
try:
    import cv2
    HAS_OPENCV = True
except ImportError:
    HAS_OPENCV = False
    logging.warning("OpenCV not available, using fallback detection methods")


def detect_rectangle_with_opencv(original_img, result_img):
    """
    Use OpenCV to detect rectangular strokes through edge analysis and line detection.
    """
    if not HAS_OPENCV:
        return None
    
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to OpenCV format (BGR)
    orig_cv = cv2.cvtColor(np.array(original_img), cv2.COLOR_RGB2BGR)
    result_cv = cv2.cvtColor(np.array(result_img), cv2.COLOR_RGB2BGR)
    
    # Convert to grayscale
    orig_gray = cv2.cvtColor(orig_cv, cv2.COLOR_BGR2GRAY)
    result_gray = cv2.cvtColor(result_cv, cv2.COLOR_BGR2GRAY)
    
    # Edge detection
    orig_edges = cv2.Canny(orig_gray, 50, 150, apertureSize=3)
    result_edges = cv2.Canny(result_gray, 50, 150, apertureSize=3)
    
    # Find NEW edges (difference between result and original)
    new_edges = cv2.bitwise_and(result_edges, cv2.bitwise_not(orig_edges))
    
    # Hough Line Transform to detect lines in new edges
    lines = cv2.HoughLinesP(new_edges, 1, np.pi/180, threshold=50, 
                           minLineLength=100, maxLineGap=20)
    
    if lines is None:
        return {
            'rectangle_detected': False,
            'horizontal_lines': 0,
            'vertical_lines': 0,
            'reason': 'No significant lines detected in new edges'
        }
    
    # Classify lines as horizontal or vertical
    horizontal_lines = []
    vertical_lines = []
    
    for line in lines:
        x1, y1, x2, y2 = line[0]
        
        # Calculate angle
        if x2 - x1 == 0:
            angle = 90  # Vertical line
        else:
            angle = abs(np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi)
        
        # Classify based on angle
        if angle < 15 or angle > 165:  # Horizontal (allowing some tolerance)
            horizontal_lines.append(line)
        elif 75 < angle < 105:  # Vertical (allowing some tolerance)
            vertical_lines.append(line)
    
    # Check for rectangle pattern (need at least 2 horizontal and 2 vertical lines)
    rectangle_detected = len(horizontal_lines) >= 2 and len(vertical_lines) >= 2
    
    # Additional validation: check if lines form roughly centered pattern
    img_width, img_height = result_img.size
    center_x, center_y = img_width // 2, img_height // 2
    
    # Calculate average position of detected lines
    all_lines = horizontal_lines + vertical_lines
    if all_lines:
        avg_x = np.mean([np.mean([line[0][0], line[0][2]]) for line in all_lines])
        avg_y = np.mean([np.mean([line[0][1], line[0][3]]) for line in all_lines])
        
        # Check if pattern is roughly centered
        center_tolerance = 0.3  # 30% of image size
        x_centered = abs(avg_x - center_x) < img_width * center_tolerance
        y_centered = abs(avg_y - center_y) < img_height * center_tolerance
        is_centered = x_centered and y_centered
    else:
        is_centered = False
    
    return {
        'rectangle_detected': rectangle_detected,
        'horizontal_lines': len(horizontal_lines),
        'vertical_lines': len(vertical_lines),
        'is_centered': is_centered,
        'total_lines': len(lines),
        'reason': f"Found {len(horizontal_lines)} horizontal and {len(vertical_lines)} vertical lines"
    }


def detect_rectangle_fallback(original_img, result_img):
    """
    Fallback rectangle detection using simple pixel difference analysis.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Find significantly changed pixels
    threshold = np.percentile(diff_magnitude, 95)  # Top 5% of changes
    changed_pixels = diff_magnitude > max(threshold, 30)
    
    # Analyze spatial distribution of changes
    height, width = changed_pixels.shape
    
    # Check for rectangular patterns by analyzing projections
    # Horizontal projection (sum along width)
    h_projection = np.sum(changed_pixels, axis=1)
    # Vertical projection (sum along height) 
    v_projection = np.sum(changed_pixels, axis=0)
    
    # Look for peaks in projections (indicating edges)
    h_peaks = []
    v_peaks = []
    
    # Find horizontal peaks (top and bottom edges)
    h_threshold = np.max(h_projection) * 0.3  # 30% of max
    for i in range(len(h_projection)):
        if h_projection[i] > h_threshold:
            h_peaks.append(i)
    
    # Find vertical peaks (left and right edges)
    v_threshold = np.max(v_projection) * 0.3  # 30% of max
    for i in range(len(v_projection)):
        if v_projection[i] > v_threshold:
            v_peaks.append(i)
    
    # Check if peaks suggest rectangular pattern
    has_top_bottom = len(h_peaks) >= 20  # Reasonable spread for rectangle edges
    has_left_right = len(v_peaks) >= 20  # Reasonable spread for rectangle edges
    
    # Check centering by looking at peak distribution
    if h_peaks:
        h_center = np.mean(h_peaks)
        h_centered = abs(h_center - height/2) < height * 0.3
    else:
        h_centered = False
        
    if v_peaks:
        v_center = np.mean(v_peaks)  
        v_centered = abs(v_center - width/2) < width * 0.3
    else:
        v_centered = False
    
    is_centered = h_centered and v_centered
    rectangle_detected = has_top_bottom and has_left_right
    
    return {
        'rectangle_detected': rectangle_detected,
        'horizontal_changes': len(h_peaks),
        'vertical_changes': len(v_peaks),
        'is_centered': is_centered,
        'change_percentage': np.mean(changed_pixels) * 100,
        'reason': f"Projection analysis: {len(h_peaks)} h-changes, {len(v_peaks)} v-changes"
    }


def check_image_modification(original_img, result_img):
    """Check if the image was meaningfully modified."""
    # Ensure same size and format
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
        
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Simple pixel comparison
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate difference
    if len(orig_array.shape) == 3:  # Color image
        diff = np.sum(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)), axis=2)
    else:  # Grayscale
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Percentage of significantly changed pixels
    changed_pixels = np.sum(diff > 10)  # Threshold of 10 intensity units
    total_pixels = diff.size
    change_percentage = (changed_pixels / total_pixels) * 100
    
    return {
        'modified': change_percentage > 1,  # At least 1% of pixels changed
        'change_percentage': change_percentage,
        'mean_difference': np.mean(diff)
    }


def check_rectangle_stroke(traj, env_info, task_info):
    """
    Main verifier function for rectangle stroke task.
    Checks:
    1. Image was modified from original
    2. Rectangular edges were detected
    3. Rectangle is roughly centered
    4. Rectangle is appropriately sized
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # Set up verification environment with fallback file search
    possible_results = [
        "/home/ga/Desktop/rectangle_stroke.jpg",
        "/home/ga/Desktop/rectangle_stroke.png", 
        "/home/ga/Desktop/rectangle_stroke.jpeg",
        "/home/ga/Desktop/landscape_stroke_edited.jpg",
        "/home/ga/Desktop/landscape_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_stroke.jpg",
        possible_results,
        copy_from_env,
        "/home/ga/Desktop"
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": file_info.get("error", "Setup failed")
        }
    
    try:
        # Load images from copied files
        original_image = Image.open(file_info["original_path"])
        result_image = Image.open(file_info["result_path"])
        
        logging.debug(f"Found result image at: {file_info['result_container_path']}")
        
        # Check if image was modified
        modification_check = check_image_modification(original_image, result_image)
        
        # Try OpenCV-based rectangle detection first
        if HAS_OPENCV:
            detection_result = detect_rectangle_with_opencv(original_image, result_image)
            detection_method = "OpenCV edge detection"
        else:
            detection_result = detect_rectangle_fallback(original_image, result_image)
            detection_method = "Fallback projection analysis"
        
        # Check dimensions for appropriate sizing
        img_width, img_height = result_image.size
        min_size = min(img_width, img_height) * 0.3  # At least 30% of smaller dimension
        max_size = max(img_width, img_height) * 0.8  # At most 80% of larger dimension
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Detection method: {detection_method}")
        feedback_parts.append(f"Image modified: {'✅' if modification_check['modified'] else '❌'}")
        feedback_parts.append(f"Change percentage: {modification_check['change_percentage']:.1f}%")
        
        if HAS_OPENCV:
            feedback_parts.append(f"Horizontal lines: {detection_result['horizontal_lines']}")
            feedback_parts.append(f"Vertical lines: {detection_result['vertical_lines']}")
        else:
            feedback_parts.append(f"H-changes: {detection_result['horizontal_changes']}")
            feedback_parts.append(f"V-changes: {detection_result['vertical_changes']}")
        
        feedback_parts.append(f"Rectangle detected: {'✅' if detection_result['rectangle_detected'] else '❌'}")
        feedback_parts.append(f"Properly centered: {'✅' if detection_result['is_centered'] else '❌'}")
        feedback_parts.append(f"Detection reason: {detection_result['reason']}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if modification_check['modified']:
            criteria_met += 1
        if detection_result['rectangle_detected']:
            criteria_met += 1
        if detection_result['is_centered']:
            criteria_met += 1
        if modification_check['change_percentage'] >= 2:  # Substantial change
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rectangular stroke!")
        elif passed:
            feedback_parts.append("✅ Good rectangular stroke!")
        else:
            feedback_parts.append("❌ Rectangular stroke needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rectangle stroke verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Clean up temporary files
        cleanup_verification_environment(file_info.get("temp_dir", ""))


if __name__ == "__main__":
    # Test the verifier
    result = check_rectangle_stroke([], {}, {})
    print(f"Test result: {result}")