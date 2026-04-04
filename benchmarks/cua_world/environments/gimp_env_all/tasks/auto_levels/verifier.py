#!/usr/bin/env python3
"""
Verifier for GIMP auto levels task.
Checks if auto levels enhancement was applied to improve image exposure and contrast.
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


def calculate_tonal_metrics(image):
    """
    Calculate comprehensive tonal range and contrast metrics for image analysis.
    """
    # Convert to grayscale for analysis
    if image.mode != 'L':
        gray = image.convert('L')
    else:
        gray = image
        
    img_array = np.array(gray)
    
    # Dynamic range (spread of pixel values actually used)
    non_zero_pixels = img_array[img_array > 5]  # Exclude near-black
    non_max_pixels = non_zero_pixels[non_zero_pixels < 250]  # Exclude near-white
    
    if len(non_max_pixels) > 0:
        dynamic_range = np.max(non_max_pixels) - np.min(non_max_pixels)
        actual_min = np.min(non_max_pixels)
        actual_max = np.max(non_max_pixels)
    else:
        dynamic_range = 0
        actual_min = 0
        actual_max = 255
    
    # Overall contrast (standard deviation of pixel values)
    contrast = np.std(img_array)
    
    # Histogram spread (percentage of 256 levels actually used)
    unique_values = len(np.unique(img_array))
    histogram_spread = unique_values / 256.0
    
    # Mean brightness
    mean_brightness = np.mean(img_array)
    
    # Histogram distribution analysis
    hist, bins = np.histogram(img_array, bins=256, range=(0, 255))
    
    # Find where most pixels are concentrated
    peak_bin = np.argmax(hist)
    
    return {
        'dynamic_range': dynamic_range,
        'contrast': contrast,
        'histogram_spread': histogram_spread,
        'mean_brightness': mean_brightness,
        'actual_min': actual_min,
        'actual_max': actual_max,
        'unique_levels': unique_values,
        'peak_brightness': peak_bin
    }


def detect_auto_levels_enhancement(original_img, result_img):
    """
    Detect if auto levels enhancement was successfully applied.
    """
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Calculate metrics for both images
    orig_metrics = calculate_tonal_metrics(original_img)
    result_metrics = calculate_tonal_metrics(result_img)
    
    # Calculate improvements
    contrast_improvement = (result_metrics['contrast'] - orig_metrics['contrast']) / max(orig_metrics['contrast'], 1)
    range_improvement = (result_metrics['dynamic_range'] - orig_metrics['dynamic_range']) / max(orig_metrics['dynamic_range'], 1)
    spread_improvement = result_metrics['histogram_spread'] - orig_metrics['histogram_spread']
    brightness_change = result_metrics['mean_brightness'] - orig_metrics['mean_brightness']
    
    return {
        'original_contrast': orig_metrics['contrast'],
        'result_contrast': result_metrics['contrast'],
        'original_range': orig_metrics['dynamic_range'],
        'result_range': result_metrics['dynamic_range'],
        'original_spread': orig_metrics['histogram_spread'],
        'result_spread': result_metrics['histogram_spread'],
        'original_brightness': orig_metrics['mean_brightness'],
        'result_brightness': result_metrics['mean_brightness'],
        'contrast_improvement': contrast_improvement,
        'range_improvement': range_improvement,
        'spread_improvement': spread_improvement,
        'brightness_change': brightness_change
    }


def check_meaningful_enhancement(original_img, result_img):
    """Check if the images are meaningfully different (enhanced)."""
    # Convert to arrays for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_enhanced': change_percentage > 10  # At least 10% of pixels enhanced
    }


def check_auto_levels(traj, env_info, task_info):
    """
    Main verifier function for auto levels task.
    Checks:
    1. Dynamic range was improved (better tonal distribution)
    2. Contrast was enhanced (higher standard deviation)
    3. Histogram was stretched (better use of available range)
    4. Image was meaningfully modified
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
        "/home/ga/Desktop/auto_levels_enhanced.jpg",
        "/home/ga/Desktop/auto_levels_enhanced.png",
        "/home/ga/Desktop/auto_levels_enhanced.jpeg",
        "/home/ga/Desktop/enhanced.jpg",
        "/home/ga/Desktop/levels_enhanced.jpg",
        "/home/ga/Desktop/underexposed_image_enhanced.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/underexposed_image.jpg",
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
        
        # Analyze enhancement
        enhancement_analysis = detect_auto_levels_enhancement(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_enhancement(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original contrast: {enhancement_analysis['original_contrast']:.1f}")
        feedback_parts.append(f"Result contrast: {enhancement_analysis['result_contrast']:.1f}")
        feedback_parts.append(f"Contrast improvement: {enhancement_analysis['contrast_improvement']:.1%}")
        feedback_parts.append(f"Original range: {enhancement_analysis['original_range']:.0f}")
        feedback_parts.append(f"Result range: {enhancement_analysis['result_range']:.0f}")
        feedback_parts.append(f"Original brightness: {enhancement_analysis['original_brightness']:.1f}")
        feedback_parts.append(f"Result brightness: {enhancement_analysis['result_brightness']:.1f}")
        feedback_parts.append(f"Pixels enhanced: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Dynamic range improved
        range_improved = enhancement_analysis['result_range'] > enhancement_analysis['original_range']
        if range_improved:
            criteria_met += 1
        feedback_parts.append(f"Dynamic range improved: {'✅' if range_improved else '❌'}")
        
        # 2. Contrast enhanced (at least 15% improvement)
        contrast_enhanced = enhancement_analysis['contrast_improvement'] >= 0.15
        if contrast_enhanced:
            criteria_met += 1
        feedback_parts.append(f"Contrast enhanced (≥15%): {'✅' if contrast_enhanced else '❌'}")
        
        # 3. Histogram stretched (better distribution)
        histogram_stretched = enhancement_analysis['spread_improvement'] > 0.05
        if histogram_stretched:
            criteria_met += 1
        feedback_parts.append(f"Histogram stretched: {'✅' if histogram_stretched else '❌'}")
        
        # 4. Meaningful enhancement detected
        if change_analysis['meaningfully_enhanced']:
            criteria_met += 1
        feedback_parts.append(f"Image enhanced: {'✅' if change_analysis['meaningfully_enhanced'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent auto levels enhancement!")
        elif passed:
            feedback_parts.append("✅ Good auto levels enhancement!")
        else:
            feedback_parts.append("❌ Auto levels enhancement needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in auto levels verification: {e}")
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
    result = check_auto_levels([], {}, {})
    print(f"Test result: {result}")