#!/usr/bin/env python3
"""
Verifier for GIMP invert colors task.
Checks if all colors were mathematically inverted using the formula: new_value = 255 - original_value.
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


def verify_mathematical_inversion(original_img, result_img, tolerance=2):
    """
    Verify that the result image is a mathematical inversion of the original.
    Uses the formula: new_value = 255 - original_value for each RGB channel.
    """
    # Ensure both images are in RGB mode
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Resize result to match original if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate expected inverted values: 255 - original
    expected_array = 255 - orig_array
    
    # Calculate pixel-wise differences between result and expected
    diff = np.abs(result_array.astype(np.int16) - expected_array.astype(np.int16))
    
    # Check how many pixels are within tolerance
    within_tolerance = diff <= tolerance
    
    # Calculate match percentages for each channel
    red_match = np.mean(within_tolerance[:, :, 0]) * 100
    green_match = np.mean(within_tolerance[:, :, 1]) * 100
    blue_match = np.mean(within_tolerance[:, :, 2]) * 100
    overall_match = np.mean(within_tolerance) * 100
    
    return {
        'overall_match': overall_match,
        'red_channel_match': red_match,
        'green_channel_match': green_match,
        'blue_channel_match': blue_match,
        'mathematically_inverted': overall_match >= 95  # Require 95% accuracy
    }


def analyze_color_histograms(original_img, result_img):
    """
    Analyze color distribution changes to verify inversion occurred.
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate brightness distributions
    orig_brightness = np.mean(orig_array, axis=2).flatten()
    result_brightness = np.mean(result_array, axis=2).flatten()
    
    orig_avg_brightness = np.mean(orig_brightness)
    result_avg_brightness = np.mean(result_brightness)
    
    # In perfect inversion, bright areas become dark and vice versa
    expected_brightness = 255 - orig_avg_brightness
    brightness_inversion_accuracy = 100 - abs(result_avg_brightness - expected_brightness) / 255 * 100
    
    return {
        'original_avg_brightness': orig_avg_brightness,
        'result_avg_brightness': result_avg_brightness,
        'expected_avg_brightness': expected_brightness,
        'brightness_inversion_accuracy': brightness_inversion_accuracy,
        'good_brightness_inversion': brightness_inversion_accuracy >= 90
    }


def detect_meaningful_transformation(original_img, result_img):
    """
    Check if the image underwent meaningful transformation.
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff_per_channel = np.mean(diff, axis=(0, 1))
    overall_mean_diff = np.mean(mean_diff_per_channel)
    
    # Calculate percentage of significantly changed pixels
    significant_change_threshold = 50  # Pixels that changed by more than 50 intensity units
    significant_changes = np.sqrt(np.sum(diff ** 2, axis=2)) > significant_change_threshold
    change_percentage = np.mean(significant_changes) * 100
    
    return {
        'mean_pixel_difference': overall_mean_diff,
        'significant_change_percentage': change_percentage,
        'meaningfully_transformed': change_percentage > 80  # At least 80% of pixels significantly changed
    }


def check_color_inversion(traj, env_info, task_info):
    """
    Main verifier function for color inversion task.
    Checks:
    1. Mathematical accuracy of RGB inversion (255 - original)
    2. Complete coverage of the transformation
    3. Quality preservation and proper transformation
    4. Meaningful image modification occurred
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
        "/home/ga/Desktop/inverted_colors.jpg",
        "/home/ga/Desktop/inverted_colors.png",
        "/home/ga/Desktop/inverted_colors.jpeg",
        "/home/ga/Desktop/colorful_landscape_inverted.jpg",
        "/home/ga/Desktop/landscape_inverted.jpg",
        "/home/ga/Desktop/colorful_landscape.jpg"  # In case they modified in place
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/colorful_landscape.jpg",
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
        
        # Verify mathematical inversion
        inversion_analysis = verify_mathematical_inversion(original_image, result_image)
        
        # Analyze histogram changes
        histogram_analysis = analyze_color_histograms(original_image, result_image)
        
        # Check for meaningful transformation
        transform_analysis = detect_meaningful_transformation(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Mathematical accuracy: {inversion_analysis['overall_match']:.1f}%")
        feedback_parts.append(f"Red channel match: {inversion_analysis['red_channel_match']:.1f}%")
        feedback_parts.append(f"Green channel match: {inversion_analysis['green_channel_match']:.1f}%")
        feedback_parts.append(f"Blue channel match: {inversion_analysis['blue_channel_match']:.1f}%")
        feedback_parts.append(f"Brightness inversion: {histogram_analysis['brightness_inversion_accuracy']:.1f}%")
        feedback_parts.append(f"Pixels significantly changed: {transform_analysis['significant_change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Mathematical RGB inversion accuracy
        if inversion_analysis['mathematically_inverted']:
            criteria_met += 1
        feedback_parts.append(f"Mathematical inversion: {'✅' if inversion_analysis['mathematically_inverted'] else '❌'}")
        
        # 2. Complete coverage (meaningful transformation)
        if transform_analysis['meaningfully_transformed']:
            criteria_met += 1
        feedback_parts.append(f"Complete coverage: {'✅' if transform_analysis['meaningfully_transformed'] else '❌'}")
        
        # 3. Good brightness relationship inversion
        if histogram_analysis['good_brightness_inversion']:
            criteria_met += 1
        feedback_parts.append(f"Brightness inversion: {'✅' if histogram_analysis['good_brightness_inversion'] else '❌'}")
        
        # 4. Quality preservation (dimensions unchanged)
        dimensions_preserved = original_image.size == result_image.size
        if dimensions_preserved:
            criteria_met += 1
        feedback_parts.append(f"Quality preserved: {'✅' if dimensions_preserved else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect color inversion!")
        elif passed:
            feedback_parts.append("✅ Good color inversion!")
        else:
            feedback_parts.append("❌ Color inversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color inversion verification: {e}")
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
    result = check_color_inversion([], {}, {})
    print(f"Test result: {result}")