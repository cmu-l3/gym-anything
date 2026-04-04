#!/usr/bin/env python3
"""
Verifier for GIMP square crop task.
Checks if image was cropped to create a perfect square (1:1 aspect ratio).
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


def check_square_dimensions(img, tolerance=2):
    """Check if image has perfectly square dimensions (width equals height)."""
    width, height = img.size
    
    # Calculate difference between width and height
    dimension_diff = abs(width - height)
    is_square = dimension_diff <= tolerance
    
    # Calculate aspect ratio
    aspect_ratio = width / height if height > 0 else float('inf')
    aspect_ratio_ok = 0.98 <= aspect_ratio <= 1.02  # ±2% tolerance
    
    return {
        'is_square': is_square,
        'dimension_diff': dimension_diff,
        'aspect_ratio': aspect_ratio,
        'aspect_ratio_ok': aspect_ratio_ok,
        'dimensions': (width, height)
    }


def check_cropping_occurred(original_img, result_img):
    """
    Check if significant cropping occurred compared to original.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate area reduction
    orig_area = orig_width * orig_height
    result_area = result_width * result_height
    area_ratio = result_area / orig_area if orig_area > 0 else 0
    
    # Check if at least one dimension was reduced
    width_decreased = result_width < orig_width
    height_decreased = result_height < orig_height
    was_cropped = width_decreased or height_decreased
    
    # Check for significant crop (not just tiny edge removal)
    width_ratio = result_width / orig_width if orig_width > 0 else 0
    height_ratio = result_height / orig_height if orig_height > 0 else 0
    significant_crop = width_ratio < 0.95 or height_ratio < 0.95
    
    return {
        'was_cropped': was_cropped,
        'significant_crop': significant_crop,
        'area_ratio': area_ratio,
        'width_ratio': width_ratio,
        'height_ratio': height_ratio,
        'area_reduction_percent': (1 - area_ratio) * 100
    }


def check_reasonable_size(img, min_dimension=100):
    """Check if the resulting square has reasonable minimum dimensions."""
    width, height = img.size
    min_dim = min(width, height)
    reasonable_size = min_dim >= min_dimension
    
    return {
        'reasonable_size': reasonable_size,
        'min_dimension': min_dim,
        'required_min': min_dimension
    }


def check_square_crop(traj, env_info, task_info):
    """
    Main verifier function for square crop task.
    Checks:
    1. Image is perfectly square (width equals height)
    2. Aspect ratio is 1:1 (±2% tolerance)
    3. Cropping actually occurred (not just resize)
    4. Result has reasonable minimum size
    5. Significant cropping was applied
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
        "/home/ga/Desktop/square_crop.jpg",
        "/home/ga/Desktop/square_crop.png", 
        "/home/ga/Desktop/square_crop.jpeg",
        "/home/ga/Desktop/landscape_square.jpg",
        "/home/ga/Desktop/cropped_square.jpg",
        "/home/ga/Desktop/landscape_image_cropped.jpg"
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
        
        # Check square dimensions
        square_check = check_square_dimensions(result_image, tolerance=2)
        
        # Check if cropping occurred
        crop_check = check_cropping_occurred(original_image, result_image)
        
        # Check reasonable size
        size_check = check_reasonable_size(result_image, min_dimension=100)
        
        # Check if image was modified
        images_different = (original_image.size != result_image.size or 
                          not np.array_equal(np.array(original_image), 
                                           np.array(result_image.convert(original_image.mode))))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Dimension difference: {square_check['dimension_diff']}px")
        feedback_parts.append(f"Aspect ratio: {square_check['aspect_ratio']:.3f}")
        feedback_parts.append(f"Area reduction: {crop_check['area_reduction_percent']:.1f}%")
        feedback_parts.append(f"Perfect square: {'✅' if square_check['is_square'] else '❌'}")
        feedback_parts.append(f"1:1 aspect ratio: {'✅' if square_check['aspect_ratio_ok'] else '❌'}")
        feedback_parts.append(f"Actually cropped: {'✅' if crop_check['was_cropped'] else '❌'}")
        feedback_parts.append(f"Reasonable size: {'✅' if size_check['reasonable_size'] else '❌'}")
        feedback_parts.append(f"Significant crop: {'✅' if crop_check['significant_crop'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        if square_check['is_square']:
            criteria_met += 1
        if square_check['aspect_ratio_ok']:
            criteria_met += 1
        if crop_check['was_cropped']:
            criteria_met += 1
        if size_check['reasonable_size']:
            criteria_met += 1
        if crop_check['significant_crop']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect square crop!")
        elif passed:
            feedback_parts.append("✅ Good square crop!")
        else:
            feedback_parts.append("❌ Square crop needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in square crop verification: {e}")
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
    result = check_square_crop([], {}, {})
    print(f"Test result: {result}")