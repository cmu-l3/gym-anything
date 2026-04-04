#!/usr/bin/env python3
"""
Verifier for GIMP scale by percentage task.
Checks if image was scaled to 50% of original size while maintaining aspect ratio.
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


def check_scaling_accuracy(original_img, result_img, target_percent=50, tolerance=3):
    """
    Check if image was scaled to target percentage with given tolerance.
    Returns scaling ratios for width and height.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Calculate actual scale ratios as percentages
    width_ratio = (result_w / orig_w) * 100
    height_ratio = (result_h / orig_h) * 100
    
    # Check if both dimensions are within tolerance of target
    width_accurate = abs(width_ratio - target_percent) <= tolerance
    height_accurate = abs(height_ratio - target_percent) <= tolerance
    
    return {
        'width_ratio': width_ratio,
        'height_ratio': height_ratio,
        'width_accurate': width_accurate,
        'height_accurate': height_accurate,
        'target_percent': target_percent,
        'tolerance': tolerance
    }


def check_aspect_ratio_preservation(original_img, result_img, tolerance=0.02):
    """
    Check if aspect ratio was maintained during scaling.
    Returns aspect ratio analysis.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Calculate aspect ratios
    orig_aspect = orig_w / orig_h
    result_aspect = result_w / result_h
    
    # Calculate relative difference
    aspect_diff = abs(result_aspect - orig_aspect) / orig_aspect
    aspect_preserved = aspect_diff <= tolerance
    
    return {
        'orig_aspect': orig_aspect,
        'result_aspect': result_aspect,
        'aspect_diff_percent': aspect_diff * 100,
        'aspect_preserved': aspect_preserved,
        'tolerance_percent': tolerance * 100
    }


def verify_meaningful_downscale(original_img, result_img):
    """
    Verify that image was actually downsized (not upscaled or unchanged).
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Check that both dimensions are smaller
    width_smaller = result_w < orig_w
    height_smaller = result_h < orig_h
    meaningfully_smaller = width_smaller and height_smaller
    
    # Calculate area reduction
    orig_area = orig_w * orig_h
    result_area = result_w * result_h
    area_reduction_percent = ((orig_area - result_area) / orig_area) * 100
    
    return {
        'width_smaller': width_smaller,
        'height_smaller': height_smaller,
        'meaningfully_downscaled': meaningfully_smaller,
        'area_reduction_percent': area_reduction_percent
    }


def check_minimum_size_requirements(result_img, min_dimension=50):
    """
    Ensure result image is not too small to be useful.
    """
    width, height = result_img.size
    meets_minimum = width >= min_dimension and height >= min_dimension
    
    return {
        'width': width,
        'height': height,
        'meets_minimum': meets_minimum,
        'min_required': min_dimension
    }


def check_percentage_scaling(traj, env_info, task_info):
    """
    Main verifier function for percentage scaling task.
    Checks:
    1. Image was scaled to approximately 50% of original dimensions
    2. Aspect ratio was preserved during scaling
    3. Image was meaningfully downscaled (not upscaled)
    4. Result meets minimum size requirements
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
        "/home/ga/Desktop/scaled_50_percent.png",
        "/home/ga/Desktop/scaled_50_percent.jpg", 
        "/home/ga/Desktop/scaled_50_percent.jpeg",
        "/home/ga/Desktop/test_scale_image_scaled.jpg",
        "/home/ga/Desktop/scaled_image.png",
        "/home/ga/Desktop/test_scale_50.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/test_scale_image.jpg",
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
        
        # Perform scaling accuracy analysis
        scaling_analysis = check_scaling_accuracy(original_image, result_image, target_percent=50, tolerance=3)
        
        # Check aspect ratio preservation
        aspect_analysis = check_aspect_ratio_preservation(original_image, result_image, tolerance=0.02)
        
        # Verify meaningful downscale
        downscale_analysis = verify_meaningful_downscale(original_image, result_image)
        
        # Check minimum size requirements
        size_analysis = check_minimum_size_requirements(result_image, min_dimension=50)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Width scaling: {scaling_analysis['width_ratio']:.1f}% (target: 50%)")
        feedback_parts.append(f"Height scaling: {scaling_analysis['height_ratio']:.1f}% (target: 50%)")
        feedback_parts.append(f"Aspect ratio change: {aspect_analysis['aspect_diff_percent']:.1f}%")
        feedback_parts.append(f"Area reduction: {downscale_analysis['area_reduction_percent']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Width scaled correctly to ~50%
        if scaling_analysis['width_accurate']:
            criteria_met += 1
        feedback_parts.append(f"Width scaled correctly: {'✅' if scaling_analysis['width_accurate'] else '❌'}")
        
        # 2. Height scaled correctly to ~50%
        if scaling_analysis['height_accurate']:
            criteria_met += 1
        feedback_parts.append(f"Height scaled correctly: {'✅' if scaling_analysis['height_accurate'] else '❌'}")
        
        # 3. Aspect ratio maintained
        if aspect_analysis['aspect_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Aspect ratio maintained: {'✅' if aspect_analysis['aspect_preserved'] else '❌'}")
        
        # 4. Meaningfully downscaled
        if downscale_analysis['meaningfully_downscaled']:
            criteria_met += 1
        feedback_parts.append(f"Properly downscaled: {'✅' if downscale_analysis['meaningfully_downscaled'] else '❌'}")
        
        # Check minimum size (bonus criterion, doesn't affect pass/fail but affects score)
        meets_size_req = size_analysis['meets_minimum']
        feedback_parts.append(f"Meets size requirements: {'✅' if meets_size_req else '❌'}")
        
        # Calculate score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        
        # Bonus points for meeting size requirements
        if meets_size_req and score >= 75:
            score = min(100, score + 5)
        
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect 50% scaling with maintained aspect ratio!")
        elif passed:
            feedback_parts.append("✅ Good percentage scaling!")
        else:
            feedback_parts.append("❌ Scaling accuracy or aspect ratio needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in percentage scaling verification: {e}")
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
    result = check_percentage_scaling([], {}, {})
    print(f"Test result: {result}")