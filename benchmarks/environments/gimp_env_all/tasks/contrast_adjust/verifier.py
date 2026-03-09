#!/usr/bin/env python3
"""
Verifier for GIMP contrast adjustment task.
Checks if image contrast was increased using statistical analysis.
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


def calculate_contrast_metric(img):
    """
    Calculate contrast using standard deviation of pixel intensities.
    Standard deviation is a robust measure of tonal spread.
    """
    # Convert to grayscale for luminosity analysis
    if img.mode != 'L':
        gray_img = img.convert('L')
    else:
        gray_img = img
    
    # Convert to numpy array
    pixels = np.array(gray_img)
    
    # Calculate standard deviation (contrast measure)
    contrast = np.std(pixels.astype(np.float32))
    
    return contrast


def check_clipping(img):
    """
    Check if excessive clipping occurred in highlights or shadows.
    Returns clipping percentage and whether it's acceptable.
    """
    if img.mode != 'L':
        gray_img = img.convert('L')
    else:
        gray_img = img
    
    pixels = np.array(gray_img)
    
    # Count pixels at extremes (pure black and pure white)
    black_pixels = np.sum(pixels == 0)
    white_pixels = np.sum(pixels == 255)
    total_pixels = pixels.size
    
    # Calculate clipping percentage
    clipping_percentage = (black_pixels + white_pixels) / total_pixels
    
    # Allow up to 5% clipping (common in high-contrast images)
    acceptable_clipping = clipping_percentage < 0.05
    
    return clipping_percentage, acceptable_clipping


def analyze_brightness_change(original_img, result_img):
    """
    Analyze if overall brightness changed significantly.
    We want contrast adjustment without major brightness shifts.
    """
    orig_gray = original_img.convert('L')
    result_gray = result_img.convert('L')
    
    orig_mean = np.mean(np.array(orig_gray))
    result_mean = np.mean(np.array(result_gray))
    
    brightness_change = abs(result_mean - orig_mean) / orig_mean
    
    # Allow up to 15% brightness change
    acceptable_brightness_change = brightness_change < 0.15
    
    return brightness_change, acceptable_brightness_change


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    if len(orig_array.shape) == 3:  # Color image
        pixel_diff = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        pixel_diff = diff
    
    significant_diff = np.sum(pixel_diff > 10)  # Pixels with >10 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 2  # At least 2% of pixels changed
    }


def check_contrast_adjustment(traj, env_info, task_info):
    """
    Main verifier function for contrast adjustment task.
    Checks:
    1. Contrast was meaningfully increased (10-80% improvement)
    2. No excessive clipping occurred
    3. Overall brightness wasn't dramatically altered
    4. Image was actually modified
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
        "/home/ga/Desktop/enhanced_contrast.jpg",
        "/home/ga/Desktop/enhanced_contrast.png",
        "/home/ga/Desktop/enhanced_contrast.jpeg",
        "/home/ga/Desktop/low_contrast_image_enhanced.jpg",
        "/home/ga/Desktop/contrast_adjusted.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/low_contrast_image.jpg",
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
        
        # Calculate contrast metrics
        original_contrast = calculate_contrast_metric(original_image)
        result_contrast = calculate_contrast_metric(result_image)
        
        # Calculate relative contrast increase
        if original_contrast > 0:
            contrast_increase = (result_contrast - original_contrast) / original_contrast
        else:
            contrast_increase = 0
        
        # Check for clipping
        clipping_percentage, acceptable_clipping = check_clipping(result_image)
        
        # Check brightness change
        brightness_change, acceptable_brightness = analyze_brightness_change(original_image, result_image)
        
        # Check if image was modified
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original contrast (std): {original_contrast:.2f}")
        feedback_parts.append(f"Result contrast (std): {result_contrast:.2f}")
        feedback_parts.append(f"Contrast increase: {contrast_increase:.1%}")
        feedback_parts.append(f"Clipping: {clipping_percentage:.1%}")
        feedback_parts.append(f"Brightness change: {brightness_change:.1%}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Meaningful contrast increase (10-80%)
        contrast_good = 0.10 <= contrast_increase <= 0.80
        if contrast_good:
            criteria_met += 1
        feedback_parts.append(f"Contrast increased appropriately: {'✅' if contrast_good else '❌'}")
        
        # 2. Acceptable clipping levels
        if acceptable_clipping:
            criteria_met += 1
        feedback_parts.append(f"No excessive clipping: {'✅' if acceptable_clipping else '❌'}")
        
        # 3. Brightness not dramatically altered
        if acceptable_brightness:
            criteria_met += 1
        feedback_parts.append(f"Brightness preserved: {'✅' if acceptable_brightness else '❌'}")
        
        # 4. Image was meaningfully modified
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent contrast enhancement!")
        elif passed:
            feedback_parts.append("✅ Good contrast adjustment!")
        else:
            feedback_parts.append("❌ Contrast adjustment needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in contrast adjustment verification: {e}")
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
    result = check_contrast_adjustment([], {}, {})
    print(f"Test result: {result}")