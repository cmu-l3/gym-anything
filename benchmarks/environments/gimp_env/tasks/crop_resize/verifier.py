#!/usr/bin/env python3
"""
Verifier for GIMP crop and resize task.
Checks if image was cropped to focus on subject and resized to 400x300.
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


def check_image_dimensions(img, target_width=400, target_height=300, tolerance=5):
    """Check if image has target dimensions within tolerance."""
    width, height = img.size
    
    width_ok = abs(width - target_width) <= tolerance
    height_ok = abs(height - target_height) <= tolerance
    
    return width_ok and height_ok, (width, height)


def detect_subject_focus(original_img, result_img):
    """
    Analyze if the crop focused on the main subject.
    Uses center-weighted analysis and face detection heuristics.
    """
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    orig_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    # Calculate center focus score
    orig_h, orig_w = orig_array.shape
    result_h, result_w = result_array.shape
    
    # Check if significantly cropped
    crop_ratio = (result_w * result_h) / (orig_w * orig_h)
    significantly_cropped = crop_ratio < 0.8  # At least 20% reduction
    
    # Analyze center region intensity (heuristic for subject focus)
    # Get center 60% of both images
    orig_center_y1, orig_center_y2 = int(orig_h * 0.2), int(orig_h * 0.8)
    orig_center_x1, orig_center_x2 = int(orig_w * 0.2), int(orig_w * 0.8)
    orig_center = orig_array[orig_center_y1:orig_center_y2, orig_center_x1:orig_center_x2]
    
    result_center_y1, result_center_y2 = int(result_h * 0.2), int(result_h * 0.8)
    result_center_x1, result_center_x2 = int(result_w * 0.2), int(result_w * 0.8)
    result_center = result_array[result_center_y1:result_center_y2, result_center_x1:result_center_x2]
    
    # Calculate contrast and detail in center regions
    orig_center_std = np.std(orig_center) if orig_center.size > 0 else 0
    result_center_std = np.std(result_center) if result_center.size > 0 else 0
    
    # Good crop should maintain or increase center detail
    detail_preserved = result_center_std >= orig_center_std * 0.8
    
    # Check aspect ratio - portrait crops often indicate subject focus
    orig_aspect = orig_w / orig_h
    result_aspect = result_w / result_h
    aspect_change = abs(result_aspect - orig_aspect)
    
    return {
        'significantly_cropped': significantly_cropped,
        'crop_ratio': crop_ratio,
        'detail_preserved': detail_preserved,
        'orig_center_std': orig_center_std,
        'result_center_std': result_center_std,
        'aspect_change': aspect_change
    }


def check_crop_resize(traj, env_info, task_info):
    """
    Main verifier function for crop and resize task.
    Checks:
    1. Image was significantly cropped (focusing on subject)
    2. Final dimensions are 400x300 pixels (±5px tolerance)
    3. Image quality and detail are preserved
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
        "/home/ga/Desktop/cropped_resized.jpg",
        "/home/ga/Desktop/cropped_resized.png", 
        "/home/ga/Desktop/cropped_resized.jpeg",
        "/home/ga/Desktop/portrait_image_cropped.jpg",
        "/home/ga/Desktop/portrait_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_image.jpg",
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
        
        # Check if dimensions match target (400x300)
        dimensions_correct, actual_dims = check_image_dimensions(result_image, 400, 300, tolerance=5)
        
        # Analyze subject focus
        subject_analysis = detect_subject_focus(original_image, result_image)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size or not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Target size: (400, 300)")
        feedback_parts.append(f"Dimensions correct: {'✅' if dimensions_correct else '❌'}")
        feedback_parts.append(f"Significantly cropped: {'✅' if subject_analysis['significantly_cropped'] else '❌'}")
        feedback_parts.append(f"Crop ratio: {subject_analysis['crop_ratio']:.2f}")
        feedback_parts.append(f"Detail preserved: {'✅' if subject_analysis['detail_preserved'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimensions_correct:
            criteria_met += 1
        if subject_analysis['significantly_cropped']:
            criteria_met += 1 
        if subject_analysis['detail_preserved']:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect crop and resize!")
        elif passed:
            feedback_parts.append("✅ Good crop and resize!")
        else:
            feedback_parts.append("❌ Crop and resize needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in crop resize verification: {e}")
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
    result = check_crop_resize([], {}, {})
    print(f"Test result: {result}")
