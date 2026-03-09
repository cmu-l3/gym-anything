#!/usr/bin/env python3
"""
Verifier for GIMP new layer creation task.
Checks if a new white layer was created on top of the landscape image.
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


def verify_white_layer_created(original_img, result_img):
    """
    Verify that a white-filled layer was created on top.
    Returns True if the result is predominantly white.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    
    # Count pixels that are white or near-white (all channels ≥240)
    white_pixels = np.all(result_array >= 240, axis=2)
    white_percentage = np.sum(white_pixels) / white_pixels.size
    
    logging.debug(f"White pixel percentage: {white_percentage:.2%}")
    
    # Should be predominantly white if white layer is on top
    return white_percentage >= 0.85, white_percentage


def check_significant_change(original_img, result_img):
    """
    Check if the image was significantly modified from the original.
    """
    # Ensure images are the same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert both to RGB for comparison
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise absolute differences
    differences = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Significant changes (>50 intensity units per channel)
    significant_changes = np.any(differences > 50, axis=2)
    change_percentage = np.sum(significant_changes) / significant_changes.size
    
    logging.debug(f"Significant change percentage: {change_percentage:.2%}")
    
    # Expect >80% of image to change when white layer is added
    return change_percentage >= 0.80, change_percentage


def check_white_fill_quality(result_img):
    """
    Check the quality of the white fill - should be uniform.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    
    # Find white pixels (all channels ≥240)
    white_mask = np.all(result_array >= 240, axis=2)
    
    if np.sum(white_mask) == 0:
        return False, 0.0  # No white pixels found
    
    # Among white pixels, check uniformity (low standard deviation)
    white_pixels = result_array[white_mask]
    
    # Calculate standard deviation across all channels for white pixels
    std_per_channel = np.std(white_pixels, axis=0)
    avg_std = np.mean(std_per_channel)
    
    logging.debug(f"White fill uniformity (lower is better): {avg_std:.2f}")
    
    # Good white fill should have low variance (std < 15)
    uniform_fill = avg_std < 15.0
    
    return uniform_fill, avg_std


def check_new_layer(traj, env_info, task_info):
    """
    Main verifier function for new layer creation task.
    Checks:
    1. Image is predominantly white (indicating white layer on top)
    2. Image was significantly changed from original
    3. White fill is uniform and clean
    4. File was properly exported
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
        "/home/ga/Desktop/overlay_layer_result.jpg",
        "/home/ga/Desktop/overlay_layer_result.png",
        "/home/ga/Desktop/overlay_layer_result.jpeg",
        "/home/ga/Desktop/landscape_base_with_layer.jpg",
        "/home/ga/Desktop/landscape_base_edited.jpg",
        "/home/ga/Desktop/landscape_base.xcf"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_base.jpg",
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
        
        # Check if a white layer was created (result should be predominantly white)
        white_layer_created, white_percentage = verify_white_layer_created(original_image, result_image)
        
        # Check if image was significantly modified
        significantly_changed, change_percentage = check_significant_change(original_image, result_image)
        
        # Check quality of white fill
        uniform_fill, fill_std = check_white_fill_quality(result_image)
        
        # Check if file was properly modified (not identical to original)
        images_identical = np.array_equal(np.array(original_image.convert('RGB')), 
                                        np.array(result_image.convert('RGB')))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"White pixels: {white_percentage:.1%}")
        feedback_parts.append(f"Changed pixels: {change_percentage:.1%}")
        feedback_parts.append(f"Fill uniformity: {fill_std:.1f}")
        feedback_parts.append(f"Predominantly white: {'✅' if white_layer_created else '❌'}")
        feedback_parts.append(f"Significantly changed: {'✅' if significantly_changed else '❌'}")
        feedback_parts.append(f"Uniform white fill: {'✅' if uniform_fill else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if not images_identical else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if white_layer_created:
            criteria_met += 1
        if significantly_changed:
            criteria_met += 1
        if uniform_fill:
            criteria_met += 1
        if not images_identical:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect white layer creation!")
        elif passed:
            feedback_parts.append("✅ Good white layer creation!")
        else:
            feedback_parts.append("❌ Layer creation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in new layer verification: {e}")
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
    result = check_new_layer([], {}, {})
    print(f"Test result: {result}")