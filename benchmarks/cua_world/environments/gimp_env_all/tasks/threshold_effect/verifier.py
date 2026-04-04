#!/usr/bin/env python3
"""
Verifier for GIMP threshold effect task.
Checks if image was converted to high-contrast black and white using threshold.
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


def analyze_threshold_result(result_img):
    """
    Analyze if image has been properly thresholded to black/white.
    Returns statistics about the color distribution.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    img_array = np.array(result_img)
    total_pixels = img_array.shape[0] * img_array.shape[1]
    
    # Calculate grayscale values for analysis
    gray_values = np.mean(img_array, axis=2)
    
    # Count pixels by intensity ranges (with tolerance for JPEG compression)
    black_pixels = np.sum(gray_values <= 10)      # Near-black pixels
    white_pixels = np.sum(gray_values >= 245)     # Near-white pixels
    gray_pixels = np.sum((gray_values > 10) & (gray_values < 245))  # Gray pixels
    
    # Calculate percentages
    black_percentage = (black_pixels / total_pixels) * 100
    white_percentage = (white_pixels / total_pixels) * 100
    gray_percentage = (gray_pixels / total_pixels) * 100
    binary_percentage = black_percentage + white_percentage
    
    # Check if image is properly binary (≥90% black/white, ≤5% gray)
    is_binary = binary_percentage >= 90 and gray_percentage <= 5
    
    # Check if distribution is balanced (neither color dominates too much)
    is_balanced = (15 <= black_percentage <= 85) and (15 <= white_percentage <= 85)
    
    # Analyze histogram for bimodal distribution (peaks at extremes)
    hist, bins = np.histogram(gray_values, bins=50, range=(0, 255))
    
    # Look for peaks near black (0-50) and white (200-255) ranges
    black_peak = np.max(hist[:10])  # First 10 bins (0-50 range)
    white_peak = np.max(hist[-10:])  # Last 10 bins (200-255 range)
    middle_peak = np.max(hist[15:35])  # Middle bins (around 128)
    
    has_bimodal = (black_peak > middle_peak * 2) and (white_peak > middle_peak * 2)
    
    return {
        'black_percentage': black_percentage,
        'white_percentage': white_percentage,
        'gray_percentage': gray_percentage,
        'binary_percentage': binary_percentage,
        'is_binary': is_binary,
        'is_balanced': is_balanced,
        'has_bimodal': has_bimodal,
        'total_pixels': total_pixels
    }


def check_meaningful_change(original_img, result_img):
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
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # For RGB images, calculate magnitude of change
    if len(diff.shape) == 3:
        diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    else:
        diff_magnitude = diff
    
    # Count significantly changed pixels (>30 intensity units change)
    significant_changes = np.sum(diff_magnitude > 30)
    total_pixels = diff_magnitude.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10,  # At least 10% of pixels changed significantly
        'mean_change': np.mean(diff_magnitude)
    }


def check_threshold_effect(traj, env_info, task_info):
    """
    Main verifier function for threshold effect task.
    Checks:
    1. Image converted to primarily black and white pixels (binary)
    2. Gray values eliminated (≤5% gray pixels)
    3. Balanced distribution (neither black nor white dominates completely)
    4. Image was meaningfully modified from original
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
        "/home/ga/Desktop/threshold_effect.jpg",
        "/home/ga/Desktop/threshold_effect.png",
        "/home/ga/Desktop/threshold_effect.jpeg",
        "/home/ga/Desktop/portrait_threshold_edited.jpg",
        "/home/ga/Desktop/threshold.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_threshold.jpg",
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
        
        # Analyze threshold effect
        threshold_analysis = analyze_threshold_result(result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Black pixels: {threshold_analysis['black_percentage']:.1f}%")
        feedback_parts.append(f"White pixels: {threshold_analysis['white_percentage']:.1f}%")
        feedback_parts.append(f"Gray pixels: {threshold_analysis['gray_percentage']:.1f}%")
        feedback_parts.append(f"Binary percentage: {threshold_analysis['binary_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Binary conversion (≥90% black/white pixels)
        if threshold_analysis['is_binary']:
            criteria_met += 1
        feedback_parts.append(f"Binary conversion: {'✅' if threshold_analysis['is_binary'] else '❌'}")
        
        # 2. Gray values eliminated (≤5% gray pixels)
        gray_eliminated = threshold_analysis['gray_percentage'] <= 5
        if gray_eliminated:
            criteria_met += 1
        feedback_parts.append(f"Gray values eliminated: {'✅' if gray_eliminated else '❌'}")
        
        # 3. Balanced distribution (reasonable black/white split)
        if threshold_analysis['is_balanced']:
            criteria_met += 1
        feedback_parts.append(f"Balanced distribution: {'✅' if threshold_analysis['is_balanced'] else '❌'}")
        
        # 4. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect threshold effect!")
        elif passed:
            feedback_parts.append("✅ Good threshold effect!")
        else:
            feedback_parts.append("❌ Threshold effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in threshold effect verification: {e}")
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
    result = check_threshold_effect([], {}, {})
    print(f"Test result: {result}")