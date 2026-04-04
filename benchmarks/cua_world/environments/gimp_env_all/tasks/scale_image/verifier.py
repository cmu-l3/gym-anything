#!/usr/bin/env python3
"""
Verifier for GIMP scale image task.
Checks if image was scaled to exactly 600x400 pixels.
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


def check_exact_dimensions(img, target_width=600, target_height=400):
    """Check if image has exact target dimensions."""
    width, height = img.size
    
    width_correct = (width == target_width)
    height_correct = (height == target_height)
    
    return width_correct and height_correct, (width, height)


def analyze_scaling_transformation(original_img, result_img):
    """
    Analyze if the image was actually scaled (not cropped or padded).
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Check if dimensions actually changed
    dimensions_changed = (orig_width != result_width) or (orig_height != result_height)
    
    # Calculate scaling factors
    scale_factor_w = result_width / orig_width if orig_width > 0 else 1
    scale_factor_h = result_height / orig_height if orig_height > 0 else 1
    
    # Check if scaling factors are reasonable (not too extreme)
    reasonable_scaling = (0.1 <= scale_factor_w <= 10.0) and (0.1 <= scale_factor_h <= 10.0)
    
    # Check if this looks like uniform vs non-uniform scaling
    uniform_scaling = abs(scale_factor_w - scale_factor_h) < 0.1
    
    return {
        'dimensions_changed': dimensions_changed,
        'scale_factor_w': scale_factor_w,
        'scale_factor_h': scale_factor_h,
        'reasonable_scaling': reasonable_scaling,
        'uniform_scaling': uniform_scaling
    }


def check_content_preservation(original_img, result_img):
    """
    Check if the image content was scaled rather than cropped or replaced.
    """
    # Resize original to same size as result for comparison
    if original_img.size != result_img.size:
        # Scale original to result size for comparison
        scaled_original = original_img.resize(result_img.size, Image.LANCZOS)
    else:
        scaled_original = original_img
    
    # Convert both to same mode for comparison
    if scaled_original.mode != result_img.mode:
        scaled_original = scaled_original.convert(result_img.mode)
    
    # Calculate similarity using basic pixel comparison
    orig_array = np.array(scaled_original)
    result_array = np.array(result_img)
    
    # Calculate mean absolute difference
    if orig_array.shape == result_array.shape:
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        
        # If images are very similar, it suggests proper scaling
        content_preserved = mean_diff < 50  # Allow some difference due to scaling artifacts
    else:
        content_preserved = False
        mean_diff = float('inf')
    
    return {
        'content_preserved': content_preserved,
        'mean_difference': mean_diff
    }


def check_scale_image(traj, env_info, task_info):
    """
    Main verifier function for scale image task.
    Checks:
    1. Image dimensions are exactly 600x400 pixels
    2. Image was actually scaled (dimensions changed from original)
    3. Scaling factors are reasonable
    4. Content appears to be scaled rather than cropped
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
        "/home/ga/Desktop/scaled_image.jpg",
        "/home/ga/Desktop/scaled_image.png",
        "/home/ga/Desktop/scaled_image.jpeg",
        "/home/ga/Desktop/sample_image_scaled.jpg",
        "/home/ga/Desktop/sample_scaled.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/sample_image.jpg",
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
        
        # Check exact dimensions (600x400)
        dimensions_correct, actual_dims = check_exact_dimensions(result_image, 600, 400)
        
        # Analyze scaling transformation
        scaling_analysis = analyze_scaling_transformation(original_image, result_image)
        
        # Check content preservation  
        content_analysis = check_content_preservation(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Target size: (600, 400)")
        feedback_parts.append(f"Exact dimensions: {'✅' if dimensions_correct else '❌'}")
        feedback_parts.append(f"Dimensions changed: {'✅' if scaling_analysis['dimensions_changed'] else '❌'}")
        feedback_parts.append(f"Scale factors: W={scaling_analysis['scale_factor_w']:.2f}, H={scaling_analysis['scale_factor_h']:.2f}")
        feedback_parts.append(f"Reasonable scaling: {'✅' if scaling_analysis['reasonable_scaling'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_analysis['content_preserved'] else '❌'}")
        
        # Calculate success based on criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Exact dimensions (600x400)
        if dimensions_correct:
            criteria_met += 1
        
        # 2. Dimensions actually changed from original
        if scaling_analysis['dimensions_changed']:
            criteria_met += 1
        
        # 3. Scaling factors are reasonable
        if scaling_analysis['reasonable_scaling']:
            criteria_met += 1
        
        # 4. Content appears to be properly scaled
        if content_analysis['content_preserved']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect image scaling!")
        elif passed:
            feedback_parts.append("✅ Good image scaling!")
        else:
            feedback_parts.append("❌ Image scaling needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in scale image verification: {e}")
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
    result = check_scale_image([], {}, {})
    print(f"Test result: {result}")