#!/usr/bin/env python3
"""
Verifier for GIMP hue rotation task.
Checks if all hues were rotated by approximately 60 degrees using HSV analysis.
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


def rgb_to_hsv(rgb_array):
    """
    Convert RGB array to HSV color space.
    Returns HSV with H in [0, 360], S and V in [0, 1].
    """
    # Normalize RGB to [0, 1]
    rgb = rgb_array / 255.0
    
    # Get RGB channels
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    
    # Find min and max values
    max_val = np.maximum(np.maximum(r, g), b)
    min_val = np.minimum(np.minimum(r, g), b)
    diff = max_val - min_val
    
    # Initialize HSV arrays
    h = np.zeros_like(max_val)
    s = np.zeros_like(max_val)
    v = max_val
    
    # Calculate saturation (avoid division by zero)
    non_zero_max = max_val != 0
    s[non_zero_max] = diff[non_zero_max] / max_val[non_zero_max]
    
    # Calculate hue (avoid division by zero)
    non_zero_diff = diff != 0
    
    # Red is maximum
    red_max = (max_val == r) & non_zero_diff
    h[red_max] = (60 * ((g[red_max] - b[red_max]) / diff[red_max]) + 360) % 360
    
    # Green is maximum
    green_max = (max_val == g) & non_zero_diff
    h[green_max] = (60 * ((b[green_max] - r[green_max]) / diff[green_max]) + 120) % 360
    
    # Blue is maximum
    blue_max = (max_val == b) & non_zero_diff
    h[blue_max] = (60 * ((r[blue_max] - g[blue_max]) / diff[blue_max]) + 240) % 360
    
    return np.dstack([h, s, v])


def calculate_circular_median(angles_deg):
    """Calculate median of circular data (angles in degrees)."""
    if len(angles_deg) == 0:
        return 0
    
    # Convert to radians
    angles_rad = np.radians(angles_deg)
    
    # Convert to unit vectors
    x = np.cos(angles_rad)
    y = np.sin(angles_rad)
    
    # Calculate mean direction
    mean_x = np.mean(x)
    mean_y = np.mean(y)
    
    # Convert back to degrees
    mean_angle_rad = np.arctan2(mean_y, mean_x)
    mean_angle_deg = np.degrees(mean_angle_rad)
    
    # Ensure positive angle
    if mean_angle_deg < 0:
        mean_angle_deg += 360
    
    return mean_angle_deg


def analyze_hue_rotation(original_img, result_img):
    """
    Analyze hue rotation between original and result images.
    Returns analysis of hue shift in degrees.
    """
    # Ensure images are same size
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
    
    # Convert to HSV
    orig_hsv = rgb_to_hsv(orig_array.astype(np.float32))
    result_hsv = rgb_to_hsv(result_array.astype(np.float32))
    
    # Extract hue and saturation channels
    orig_h = orig_hsv[:, :, 0]
    orig_s = orig_hsv[:, :, 1]
    result_h = result_hsv[:, :, 0]
    result_s = result_hsv[:, :, 1]
    
    # Only analyze pixels with sufficient saturation (avoid grayscale)
    saturated_mask = (orig_s > 0.15) & (result_s > 0.15)
    
    if np.sum(saturated_mask) < 100:
        return {
            'error': 'Insufficient saturated pixels for analysis',
            'saturated_pixels': np.sum(saturated_mask),
            'hue_shift': 0,
            'shift_detected': False,
            'target_achieved': False,
            'saturation_preserved': False,
            'uniform_transformation': False
        }
    
    # Get hue values for saturated pixels
    orig_hues = orig_h[saturated_mask]
    result_hues = result_h[saturated_mask]
    orig_sats = orig_s[saturated_mask]
    result_sats = result_s[saturated_mask]
    
    # Calculate median hue values using circular statistics
    orig_median_hue = calculate_circular_median(orig_hues)
    result_median_hue = calculate_circular_median(result_hues)
    
    # Calculate hue shift (handle wraparound)
    hue_shift = (result_median_hue - orig_median_hue + 180) % 360 - 180
    hue_shift_magnitude = abs(hue_shift)
    
    # Calculate pixel-wise hue differences
    pixel_hue_diffs = (result_hues - orig_hues + 180) % 360 - 180
    uniformity_std = np.std(pixel_hue_diffs)
    
    # Check saturation preservation
    sat_change = abs(np.median(result_sats) - np.median(orig_sats))
    
    return {
        'saturated_pixels': np.sum(saturated_mask),
        'orig_median_hue': orig_median_hue,
        'result_median_hue': result_median_hue,
        'hue_shift': hue_shift,
        'hue_shift_magnitude': hue_shift_magnitude,
        'uniformity_std': uniformity_std,
        'saturation_change': sat_change,
        'shift_detected': 30 <= hue_shift_magnitude <= 120,
        'target_achieved': 40 <= hue_shift_magnitude <= 80,  # 60° ± 20°
        'saturation_preserved': sat_change < 0.1,
        'uniform_transformation': uniformity_std < 30
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Convert to arrays for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 25)  # Pixels with >25 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed
    }


def check_hue_rotation(traj, env_info, task_info):
    """
    Main verifier function for hue rotation task.
    Checks:
    1. Hue shift detected (30-120 degrees)
    2. Target hue shift achieved (60° ± 20°)
    3. Saturation values preserved
    4. Uniform transformation across image
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
        "/home/ga/Desktop/hue_rotated.jpg",
        "/home/ga/Desktop/hue_rotated.png",
        "/home/ga/Desktop/hue_rotated.jpeg",
        "/home/ga/Desktop/colorful_image_rotated.jpg",
        "/home/ga/Desktop/colorful_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/colorful_image.jpg",
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
        
        # Analyze hue rotation
        hue_analysis = analyze_hue_rotation(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Saturated pixels: {hue_analysis['saturated_pixels']}")
        
        if 'error' in hue_analysis:
            feedback_parts.append(f"Analysis error: {hue_analysis['error']}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        feedback_parts.append(f"Hue shift: {hue_analysis['hue_shift']:.1f}°")
        feedback_parts.append(f"Shift magnitude: {hue_analysis['hue_shift_magnitude']:.1f}°")
        feedback_parts.append(f"Uniformity std: {hue_analysis['uniformity_std']:.1f}°")
        feedback_parts.append(f"Saturation change: {hue_analysis['saturation_change']:.3f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Hue shift detected (30-120 degrees)
        if hue_analysis['shift_detected']:
            criteria_met += 1
        feedback_parts.append(f"Hue shift detected: {'✅' if hue_analysis['shift_detected'] else '❌'}")
        
        # 2. Target hue shift achieved (60° ± 20°)
        if hue_analysis['target_achieved']:
            criteria_met += 1
        feedback_parts.append(f"Target shift achieved: {'✅' if hue_analysis['target_achieved'] else '❌'}")
        
        # 3. Saturation preserved
        if hue_analysis['saturation_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Saturation preserved: {'✅' if hue_analysis['saturation_preserved'] else '❌'}")
        
        # 4. Uniform transformation
        if hue_analysis['uniform_transformation']:
            criteria_met += 1
        feedback_parts.append(f"Uniform transformation: {'✅' if hue_analysis['uniform_transformation'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent hue rotation!")
        elif passed:
            feedback_parts.append("✅ Good hue rotation!")
        else:
            feedback_parts.append("❌ Hue rotation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in hue rotation verification: {e}")
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
    result = check_hue_rotation([], {}, {})
    print(f"Test result: {result}")