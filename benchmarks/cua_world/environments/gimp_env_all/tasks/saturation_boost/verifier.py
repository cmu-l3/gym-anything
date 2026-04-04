#!/usr/bin/env python3
"""
Verifier for GIMP saturation boost task.
Checks if saturation was increased to make colors more vibrant.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import colorsys
import sys
import os

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def rgb_to_hsv_array(rgb_array):
    """
    Convert RGB array to HSV array using colorsys.
    """
    # Normalize RGB values to 0-1 range
    rgb_normalized = rgb_array.astype(np.float32) / 255.0
    
    # Prepare output array
    hsv_array = np.zeros_like(rgb_normalized)
    
    # Convert each pixel
    height, width, channels = rgb_normalized.shape
    for y in range(height):
        for x in range(width):
            r, g, b = rgb_normalized[y, x]
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            hsv_array[y, x] = [h, s, v]
    
    return hsv_array


def analyze_saturation_change(original_img, result_img):
    """
    Analyze saturation changes between original and result images.
    Returns statistics about saturation enhancement.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Convert RGB to HSV
    orig_hsv = rgb_to_hsv_array(orig_array)
    result_hsv = rgb_to_hsv_array(result_array)
    
    # Extract saturation channels
    orig_saturation = orig_hsv[:, :, 1]
    result_saturation = result_hsv[:, :, 1]
    
    # Extract hue and value channels for verification
    orig_hue = orig_hsv[:, :, 0]
    result_hue = result_hsv[:, :, 0]
    orig_value = orig_hsv[:, :, 2]
    result_value = result_hsv[:, :, 2]
    
    # Calculate statistics
    orig_mean_sat = np.mean(orig_saturation)
    result_mean_sat = np.mean(result_saturation)
    
    # Calculate changes
    absolute_increase = result_mean_sat - orig_mean_sat
    relative_increase = (absolute_increase / orig_mean_sat) if orig_mean_sat > 0 else 0
    
    # Check hue preservation (hue should remain relatively stable)
    hue_change = np.mean(np.abs(result_hue - orig_hue))
    
    # Check value/brightness stability
    value_change = np.mean(np.abs(result_value - orig_value))
    
    # Check for over-saturation (too many pixels near maximum saturation)
    oversaturated_pixels = np.sum(result_saturation > 0.95)
    total_pixels = result_saturation.size
    oversaturation_ratio = oversaturated_pixels / total_pixels
    
    return {
        'original_mean_saturation': orig_mean_sat,
        'result_mean_saturation': result_mean_sat,
        'absolute_increase': absolute_increase,
        'relative_increase': relative_increase,
        'hue_change': hue_change,
        'value_change': value_change,
        'oversaturation_ratio': oversaturation_ratio,
        'meaningful_increase': absolute_increase >= 0.05 or relative_increase >= 0.10
    }


def check_meaningful_modification(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Convert to arrays for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed
    }


def check_saturation_boost(traj, env_info, task_info):
    """
    Main verifier function for saturation boost task.
    Checks:
    1. Saturation was meaningfully increased
    2. Hue values were preserved (no color shifts)
    3. Image was not over-saturated
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
        "/home/ga/Desktop/vibrant_colors.jpg",
        "/home/ga/Desktop/vibrant_colors.png",
        "/home/ga/Desktop/vibrant_colors.jpeg",
        "/home/ga/Desktop/landscape_enhanced.jpg",
        "/home/ga/Desktop/landscape_nature_enhanced.jpg",
        "/home/ga/Desktop/landscape_nature_saturated.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_nature.jpg",
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
        
        # Analyze saturation changes
        saturation_analysis = analyze_saturation_change(original_image, result_image)
        
        # Check for meaningful modification
        modification_analysis = check_meaningful_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original mean saturation: {saturation_analysis['original_mean_saturation']:.3f}")
        feedback_parts.append(f"Result mean saturation: {saturation_analysis['result_mean_saturation']:.3f}")
        feedback_parts.append(f"Absolute increase: {saturation_analysis['absolute_increase']:.3f}")
        feedback_parts.append(f"Relative increase: {saturation_analysis['relative_increase']:.1%}")
        feedback_parts.append(f"Hue change: {saturation_analysis['hue_change']:.3f}")
        feedback_parts.append(f"Value change: {saturation_analysis['value_change']:.3f}")
        feedback_parts.append(f"Over-saturation ratio: {saturation_analysis['oversaturation_ratio']:.1%}")
        feedback_parts.append(f"Pixels changed: {modification_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Meaningful saturation increase
        if saturation_analysis['meaningful_increase']:
            criteria_met += 1
        feedback_parts.append(f"Saturation increased meaningfully: {'✅' if saturation_analysis['meaningful_increase'] else '❌'}")
        
        # 2. Hue preservation (small hue change indicates colors weren't shifted)
        hue_preserved = saturation_analysis['hue_change'] < 0.05  # Less than 5% hue change
        if hue_preserved:
            criteria_met += 1
        feedback_parts.append(f"Hue preserved: {'✅' if hue_preserved else '❌'}")
        
        # 3. Not over-saturated (less than 15% of pixels at maximum saturation)
        not_oversaturated = saturation_analysis['oversaturation_ratio'] < 0.15
        if not_oversaturated:
            criteria_met += 1
        feedback_parts.append(f"Not over-saturated: {'✅' if not_oversaturated else '❌'}")
        
        # 4. Meaningful modification
        if modification_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent saturation enhancement!")
        elif passed:
            feedback_parts.append("✅ Good saturation boost!")
        else:
            feedback_parts.append("❌ Saturation boost needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in saturation boost verification: {e}")
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
    result = check_saturation_boost([], {}, {})
    print(f"Test result: {result}")