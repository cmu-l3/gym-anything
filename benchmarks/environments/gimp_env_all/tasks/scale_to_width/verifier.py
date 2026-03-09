#!/usr/bin/env python3
"""
Verifier for GIMP scale to width task.
Checks if image was scaled to 800px width while maintaining aspect ratio.
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


def check_width_accuracy(img, target_width=800, tolerance=5):
    """Check if image has target width within tolerance."""
    width, height = img.size
    
    width_correct = abs(width - target_width) <= tolerance
    
    return width_correct, width


def verify_aspect_ratio_maintained(original_img, result_img, tolerance=0.02):
    """
    Verify that the aspect ratio was maintained during scaling.
    tolerance: Maximum allowed relative difference in aspect ratio (2% default)
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate aspect ratios
    orig_aspect = orig_width / orig_height
    result_aspect = result_width / result_height
    
    # Calculate relative difference
    aspect_diff = abs(orig_aspect - result_aspect) / orig_aspect
    aspect_maintained = aspect_diff <= tolerance
    
    return aspect_maintained, orig_aspect, result_aspect, aspect_diff


def verify_proportional_height(original_img, result_img, target_width=800, tolerance=0.02):
    """
    Verify that the height was adjusted proportionally to the width change.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate expected height based on proportional scaling
    scale_factor = target_width / orig_width
    expected_height = orig_height * scale_factor
    
    # Check if actual height matches expected height
    height_diff = abs(result_height - expected_height) / expected_height
    height_proportional = height_diff <= tolerance
    
    return height_proportional, expected_height, result_height


def check_scaling_occurred(original_img, result_img, min_change=0.05):
    """Check if meaningful scaling occurred (at least 5% size change)."""
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate scale factor
    width_scale = result_width / orig_width
    height_scale = result_height / orig_height
    
    # Check if scaling was significant
    width_change = abs(width_scale - 1.0)
    height_change = abs(height_scale - 1.0)
    
    scaling_occurred = width_change > min_change or height_change > min_change
    
    return scaling_occurred, width_scale, height_scale


def check_scale_to_width(traj, env_info, task_info):
    """
    Main verifier function for scale to width task.
    Checks:
    1. Width is 800px (±5px tolerance)
    2. Aspect ratio is maintained (within 2% tolerance)  
    3. Height adjusted proportionally
    4. Scaling actually occurred
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
        "/home/ga/Desktop/scaled_width.jpg",
        "/home/ga/Desktop/scaled_width.png",
        "/home/ga/Desktop/scaled_width.jpeg",
        "/home/ga/Desktop/landscape_scaled.jpg",
        "/home/ga/Desktop/landscape_image_scaled.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_image.jpg",
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
        
        # Check if width is correct (800px ±5px)
        width_correct, actual_width = check_width_accuracy(result_image, 800, tolerance=5)
        
        # Verify aspect ratio was maintained
        aspect_maintained, orig_aspect, result_aspect, aspect_diff = verify_aspect_ratio_maintained(
            original_image, result_image, tolerance=0.02)
        
        # Verify height was adjusted proportionally
        height_proportional, expected_height, actual_height = verify_proportional_height(
            original_image, result_image, 800, tolerance=0.02)
        
        # Check that scaling actually occurred
        scaling_occurred, width_scale, height_scale = check_scaling_occurred(
            original_image, result_image, min_change=0.05)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Target width: 800px")
        feedback_parts.append(f"Actual width: {actual_width}px")
        feedback_parts.append(f"Width correct (800±5px): {'✅' if width_correct else '❌'}")
        feedback_parts.append(f"Original aspect ratio: {orig_aspect:.3f}")
        feedback_parts.append(f"Result aspect ratio: {result_aspect:.3f}")
        feedback_parts.append(f"Aspect ratio maintained: {'✅' if aspect_maintained else '❌'}")
        feedback_parts.append(f"Expected height: {expected_height:.1f}px")
        feedback_parts.append(f"Actual height: {actual_height}px")
        feedback_parts.append(f"Height proportional: {'✅' if height_proportional else '❌'}")
        feedback_parts.append(f"Scaling occurred: {'✅' if scaling_occurred else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if width_correct:
            criteria_met += 1
        if aspect_maintained:
            criteria_met += 1
        if height_proportional:
            criteria_met += 1
        if scaling_occurred:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect proportional scaling!")
        elif passed:
            feedback_parts.append("✅ Good proportional scaling!")
        else:
            feedback_parts.append("❌ Scaling needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in scale to width verification: {e}")
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
    result = check_scale_to_width([], {}, {})
    print(f"Test result: {result}")