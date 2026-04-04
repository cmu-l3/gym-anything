#!/usr/bin/env python3
"""
Verifier for GIMP increase saturation task.
Checks if saturation was successfully increased while preserving hue values.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import colorsys

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def rgb_to_hsv_array(rgb_array):
    """Convert RGB array to HSV using colorsys for accurate conversion."""
    # Normalize RGB to 0-1 range
    rgb_normalized = rgb_array.astype(np.float32) / 255.0
    
    # Initialize HSV array
    hsv_array = np.zeros_like(rgb_normalized)
    
    # Convert each pixel using colorsys
    height, width, channels = rgb_normalized.shape
    for y in range(height):
        for x in range(width):
            r, g, b = rgb_normalized[y, x]
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            hsv_array[y, x] = [h, s, v]
    
    return hsv_array


def analyze_saturation_increase(original_img, result_img):
    """
    Analyze saturation increase using HSV color space.
    Returns detailed metrics about the saturation enhancement.
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
    
    # Convert to HSV color space
    orig_hsv = rgb_to_hsv_array(orig_array)
    result_hsv = rgb_to_hsv_array(result_array)
    
    # Extract HSV channels
    orig_hue = orig_hsv[:, :, 0]
    orig_sat = orig_hsv[:, :, 1] 
    orig_val = orig_hsv[:, :, 2]
    
    result_hue = result_hsv[:, :, 0]
    result_sat = result_hsv[:, :, 1]
    result_val = result_hsv[:, :, 2]
    
    # Filter to colored pixels (saturation > 0.1 to exclude near-grayscale)
    colored_mask = orig_sat > 0.1
    
    if np.sum(colored_mask) < (orig_sat.size * 0.1):
        return {
            'error': 'Insufficient colored pixels for analysis',
            'colored_pixel_ratio': np.sum(colored_mask) / orig_sat.size
        }
    
    # Calculate saturation metrics for colored pixels only
    orig_sat_colored = orig_sat[colored_mask]
    result_sat_colored = result_sat[colored_mask]
    
    orig_sat_mean = np.mean(orig_sat_colored)
    result_sat_mean = np.mean(result_sat_colored)
    
    absolute_increase = result_sat_mean - orig_sat_mean
    relative_increase = (absolute_increase / orig_sat_mean) if orig_sat_mean > 0 else 0
    
    # Calculate hue stability (circular distance for colored pixels)
    orig_hue_colored = orig_hue[colored_mask]
    result_hue_colored = result_hue[colored_mask]
    
    # Handle circular hue difference (0 and 1 are the same hue)
    hue_diff = np.abs(result_hue_colored - orig_hue_colored)
    # Account for circular nature: choose smaller of direct difference or wraparound
    hue_diff_circular = np.minimum(hue_diff, 1.0 - hue_diff)
    avg_hue_shift_degrees = np.mean(hue_diff_circular) * 360
    
    # Check for meaningful change in overall image
    pixel_diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    significant_change_mask = np.sqrt(np.sum(pixel_diff ** 2, axis=2)) > 15
    change_percentage = np.sum(significant_change_mask) / significant_change_mask.size * 100
    
    return {
        'original_sat_mean': orig_sat_mean,
        'result_sat_mean': result_sat_mean,
        'absolute_increase': absolute_increase,
        'relative_increase': relative_increase,
        'avg_hue_shift_degrees': avg_hue_shift_degrees,
        'change_percentage': change_percentage,
        'colored_pixel_ratio': np.sum(colored_mask) / orig_sat.size,
        'colored_pixel_count': np.sum(colored_mask)
    }


def check_saturation_increase(traj, env_info, task_info):
    """
    Main verifier function for increase saturation task.
    Checks:
    1. Saturation was significantly increased (≥15% relative or ≥0.08 absolute)
    2. Hue values remained stable (< 5° average shift)
    3. Sufficient colored pixels exist for analysis (≥10% of image)
    4. Meaningful visual change was made to the image
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
        "/home/ga/Desktop/nature_colors_enhanced.jpg",
        "/home/ga/Desktop/nature_saturated.jpg",
        "/home/ga/Desktop/nature_colors_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/nature_colors.jpg",
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
        analysis = analyze_saturation_increase(original_image, result_image)
        
        # Check for analysis errors
        if 'error' in analysis:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Analysis error: {analysis['error']}"
            }
        
        feedback_parts = []
        feedback_parts.append(f"Original saturation: {analysis['original_sat_mean']:.3f}")
        feedback_parts.append(f"Result saturation: {analysis['result_sat_mean']:.3f}")
        feedback_parts.append(f"Absolute increase: {analysis['absolute_increase']:.3f}")
        feedback_parts.append(f"Relative increase: {analysis['relative_increase']:.1%}")
        feedback_parts.append(f"Hue shift: {analysis['avg_hue_shift_degrees']:.1f}°")
        feedback_parts.append(f"Pixels changed: {analysis['change_percentage']:.1f}%")
        feedback_parts.append(f"Colored pixels: {analysis['colored_pixel_ratio']:.1%}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Saturation increased significantly (≥15% relative OR ≥0.08 absolute)
        saturation_increased = (analysis['relative_increase'] >= 0.15 or 
                               analysis['absolute_increase'] >= 0.08)
        if saturation_increased:
            criteria_met += 1
        feedback_parts.append(f"Saturation increased: {'✅' if saturation_increased else '❌'}")
        
        # 2. Hue remained stable (< 5° average shift)
        hue_stable = analysis['avg_hue_shift_degrees'] < 5.0
        if hue_stable:
            criteria_met += 1
        feedback_parts.append(f"Hue preserved: {'✅' if hue_stable else '❌'}")
        
        # 3. Sufficient colored regions for analysis (≥10% of image)
        sufficient_colors = analysis['colored_pixel_ratio'] >= 0.1
        if sufficient_colors:
            criteria_met += 1
        feedback_parts.append(f"Sufficient colored pixels: {'✅' if sufficient_colors else '❌'}")
        
        # 4. Meaningful change detected (≥5% pixels changed significantly)
        meaningful_change = analysis['change_percentage'] >= 5.0
        if meaningful_change:
            criteria_met += 1
        feedback_parts.append(f"Meaningful change: {'✅' if meaningful_change else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent saturation enhancement!")
        elif passed:
            feedback_parts.append("✅ Good saturation increase!")
        else:
            feedback_parts.append("❌ Saturation enhancement needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in saturation increase verification: {e}")
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
    result = check_saturation_increase([], {}, {})
    print(f"Test result: {result}")