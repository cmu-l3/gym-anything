#!/usr/bin/env python3
"""
Verifier for GIMP threshold binary task.
Checks if image was successfully converted to pure black and white using threshold.
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


def analyze_binary_purity(img):
    """
    Analyze how binary (black and white) an image is.
    Returns percentage of pixels that are pure black or pure white.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    total_pixels = img_array.shape[0] * img_array.shape[1]
    
    # Count pure black pixels (0, 0, 0)
    pure_black = np.sum(np.all(img_array == [0, 0, 0], axis=2))
    
    # Count pure white pixels (255, 255, 255)
    pure_white = np.sum(np.all(img_array == [255, 255, 255], axis=2))
    
    # Count near-black pixels (for compression tolerance)
    very_dark = np.sum(np.all(img_array <= [10, 10, 10], axis=2))
    
    # Count near-white pixels (for compression tolerance)
    very_light = np.sum(np.all(img_array >= [245, 245, 245], axis=2))
    
    pure_binary_pct = (pure_black + pure_white) / total_pixels * 100
    extended_binary_pct = (very_dark + very_light) / total_pixels * 100
    
    return {
        'pure_black_pixels': pure_black,
        'pure_white_pixels': pure_white,
        'pure_binary_pct': pure_binary_pct,
        'extended_binary_pct': extended_binary_pct,
        'total_pixels': total_pixels
    }


def check_bimodal_distribution(img):
    """
    Check if the image has a bimodal distribution (pixels cluster at extremes).
    """
    if img.mode != 'L':
        img_gray = img.convert('L')
    else:
        img_gray = img
    
    img_array = np.array(img_gray)
    
    # Count pixels in different ranges
    extreme_low = np.sum(img_array <= 15)      # Near black
    mid_tones = np.sum((img_array > 15) & (img_array < 240))  # Grays
    extreme_high = np.sum(img_array >= 240)    # Near white
    
    total = img_array.size
    
    return {
        'extreme_low_pct': (extreme_low / total) * 100,
        'mid_tone_pct': (mid_tones / total) * 100,
        'extreme_high_pct': (extreme_high / total) * 100,
        'is_bimodal': (mid_tones / total) < 0.15  # Less than 15% mid-tones
    }


def check_original_complexity(img):
    """
    Check if the original image had sufficient tonal complexity to warrant thresholding.
    """
    if img.mode != 'L':
        img_gray = img.convert('L')
    else:
        img_gray = img
    
    img_array = np.array(img_gray)
    
    # Calculate histogram to check tonal distribution
    hist, bins = np.histogram(img_array, bins=256, range=(0, 255))
    
    # Count how many gray levels have significant pixel counts
    significant_levels = np.sum(hist > (img_array.size * 0.001))  # At least 0.1% of pixels
    
    # Check mid-tone presence (values between 50 and 205)
    mid_tone_pixels = np.sum((img_array > 50) & (img_array < 205))
    mid_tone_pct = (mid_tone_pixels / img_array.size) * 100
    
    return {
        'significant_gray_levels': significant_levels,
        'mid_tone_pct': mid_tone_pct,
        'had_complexity': mid_tone_pct > 20.0 and significant_levels > 10
    }


def detect_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    if len(orig_array.shape) == 3:  # RGB
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        # Calculate pixels with significant change
        pixel_diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
        significant_changes = np.sum(pixel_diff_magnitude > 30)
    else:  # Grayscale
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        significant_changes = np.sum(diff > 30)
    
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed significantly
    }


def check_threshold_binary(traj, env_info, task_info):
    """
    Main verifier function for threshold binary task.
    Checks:
    1. Image was converted to mostly pure black and white pixels
    2. Bimodal distribution (pixels cluster at extremes)
    3. Original image had sufficient complexity
    4. Meaningful transformation occurred
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
        "/home/ga/Desktop/threshold_binary.png",
        "/home/ga/Desktop/threshold_binary.jpg", 
        "/home/ga/Desktop/threshold_binary.jpeg",
        "/home/ga/Desktop/binary_image.png",
        "/home/ga/Desktop/grayscale_image_threshold.jpg",
        "/home/ga/Desktop/grayscale_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/grayscale_image.jpg",
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
        
        # Analyze binary purity
        binary_analysis = analyze_binary_purity(result_image)
        
        # Check bimodal distribution
        bimodal_analysis = check_bimodal_distribution(result_image)
        
        # Check original complexity
        complexity_analysis = check_original_complexity(original_image)
        
        # Check for meaningful change
        change_analysis = detect_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Pure binary pixels: {binary_analysis['pure_binary_pct']:.1f}%")
        feedback_parts.append(f"Extended binary pixels: {binary_analysis['extended_binary_pct']:.1f}%")
        feedback_parts.append(f"Mid-tones remaining: {bimodal_analysis['mid_tone_pct']:.1f}%")
        feedback_parts.append(f"Original had complexity: {'✅' if complexity_analysis['had_complexity'] else '❌'}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Binary purity (≥85% pure black/white or ≥90% extended)
        binary_sufficient = (binary_analysis['pure_binary_pct'] >= 85.0 or 
                           binary_analysis['extended_binary_pct'] >= 90.0)
        if binary_sufficient:
            criteria_met += 1
        feedback_parts.append(f"Binary conversion sufficient: {'✅' if binary_sufficient else '❌'}")
        
        # 2. Bimodal distribution (low mid-tones)
        is_bimodal = bimodal_analysis['is_bimodal']
        if is_bimodal:
            criteria_met += 1
        feedback_parts.append(f"Bimodal distribution: {'✅' if is_bimodal else '❌'}")
        
        # 3. Original had complexity (wasn't already binary)
        had_complexity = complexity_analysis['had_complexity']
        if had_complexity:
            criteria_met += 1
        feedback_parts.append(f"Original had mid-tones: {'✅' if had_complexity else '❌'}")
        
        # 4. Meaningful transformation occurred
        was_transformed = change_analysis['meaningfully_changed']
        if was_transformed:
            criteria_met += 1
        feedback_parts.append(f"Meaningfully transformed: {'✅' if was_transformed else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect threshold binary conversion!")
        elif passed:
            feedback_parts.append("✅ Good threshold binary conversion!")
        else:
            feedback_parts.append("❌ Threshold conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in threshold binary verification: {e}")
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
    result = check_threshold_binary([], {}, {})
    print(f"Test result: {result}")