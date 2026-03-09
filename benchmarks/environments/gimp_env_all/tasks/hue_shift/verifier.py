#!/usr/bin/env python3
"""
Verifier for GIMP hue shift task.
Checks if uniform hue shift was applied to the entire image using HSV analysis.
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


def rgb_to_hsv_array(rgb_array):
    """
    Convert RGB array to HSV array.
    Returns HSV values with H in [0, 1], S in [0, 1], V in [0, 1].
    """
    rgb_array = rgb_array.astype(np.float32) / 255.0
    
    r, g, b = rgb_array[:, :, 0], rgb_array[:, :, 1], rgb_array[:, :, 2]
    
    max_val = np.maximum(r, np.maximum(g, b))
    min_val = np.minimum(r, np.minimum(g, b))
    diff = max_val - min_val
    
    # Value channel
    v = max_val
    
    # Saturation channel
    s = np.where(max_val != 0, diff / max_val, 0)
    
    # Hue channel
    h = np.zeros_like(max_val)
    
    # Red is max
    red_max = (max_val == r) & (diff != 0)
    h[red_max] = (60 * ((g[red_max] - b[red_max]) / diff[red_max]) + 360) % 360
    
    # Green is max
    green_max = (max_val == g) & (diff != 0)
    h[green_max] = (60 * ((b[green_max] - r[green_max]) / diff[green_max]) + 120) % 360
    
    # Blue is max
    blue_max = (max_val == b) & (diff != 0)
    h[blue_max] = (60 * ((r[blue_max] - g[blue_max]) / diff[blue_max]) + 240) % 360
    
    # Convert hue to [0, 1] range
    h = h / 360.0
    
    return np.stack([h, s, v], axis=2)


def circular_mean(angles):
    """
    Calculate circular mean of angles (in range [0, 1]).
    """
    if len(angles) == 0:
        return 0
    
    # Convert to radians
    angles_rad = angles * 2 * np.pi
    
    # Calculate circular mean
    sin_mean = np.mean(np.sin(angles_rad))
    cos_mean = np.mean(np.cos(angles_rad))
    mean_rad = np.arctan2(sin_mean, cos_mean)
    
    # Convert back to [0, 1] range
    return (mean_rad / (2 * np.pi)) % 1


def circular_distance(angle1, angle2):
    """
    Calculate shortest distance between two circular angles (in range [0, 1]).
    """
    diff = (angle2 - angle1) % 1
    return min(diff, 1 - diff)


def analyze_hue_shift(original_img, result_img):
    """
    Analyze uniform hue shift using HSV color space.
    """
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Convert RGB to HSV
    orig_hsv = rgb_to_hsv_array(orig_array)
    result_hsv = rgb_to_hsv_array(result_array)
    
    # Extract channels
    orig_h, orig_s, orig_v = orig_hsv[:,:,0], orig_hsv[:,:,1], orig_hsv[:,:,2]
    result_h, result_s, result_v = result_hsv[:,:,0], result_hsv[:,:,1], result_hsv[:,:,2]
    
    # Focus on pixels with significant saturation (avoid grays/blacks)
    saturated_mask = orig_s > 0.1
    
    if np.sum(saturated_mask) < 100:
        return {
            'error': 'Insufficient saturated pixels to analyze hue shift',
            'saturated_pixels': np.sum(saturated_mask)
        }
    
    # Calculate circular mean hue values for saturated pixels
    orig_hue_mean = circular_mean(orig_h[saturated_mask])
    result_hue_mean = circular_mean(result_h[saturated_mask])
    
    # Calculate hue shift (handling wraparound)
    hue_shift_magnitude = circular_distance(orig_hue_mean, result_hue_mean)
    # Convert to degrees for easier interpretation
    hue_shift_degrees = hue_shift_magnitude * 360
    
    # Check saturation and value preservation
    orig_sat_mean = np.mean(orig_s[saturated_mask])
    result_sat_mean = np.mean(result_s[saturated_mask])
    sat_ratio = result_sat_mean / orig_sat_mean if orig_sat_mean > 0 else 1
    
    orig_val_mean = np.mean(orig_v[saturated_mask])
    result_val_mean = np.mean(result_v[saturated_mask])
    val_ratio = result_val_mean / orig_val_mean if orig_val_mean > 0 else 1
    
    # Check uniformity of shift across different regions
    # Divide image into 4 quadrants and check hue shift consistency
    h, w = orig_h.shape
    quadrants = [
        (slice(0, h//2), slice(0, w//2)),          # top-left
        (slice(0, h//2), slice(w//2, w)),          # top-right
        (slice(h//2, h), slice(0, w//2)),          # bottom-left
        (slice(h//2, h), slice(w//2, w))           # bottom-right
    ]
    
    quadrant_shifts = []
    for quad_slice in quadrants:
        quad_orig_mask = saturated_mask[quad_slice] 
        if np.sum(quad_orig_mask) > 20:  # Need at least 20 saturated pixels
            quad_orig_h = orig_h[quad_slice][quad_orig_mask]
            quad_result_h = result_h[quad_slice][quad_orig_mask]
            
            quad_orig_mean = circular_mean(quad_orig_h)
            quad_result_mean = circular_mean(quad_result_h)
            quad_shift = circular_distance(quad_orig_mean, quad_result_mean) * 360
            quadrant_shifts.append(quad_shift)
    
    # Calculate uniformity (standard deviation of quadrant shifts)
    shift_uniformity = np.std(quadrant_shifts) if len(quadrant_shifts) > 1 else 0
    
    return {
        'hue_shift_degrees': hue_shift_degrees,
        'saturation_ratio': sat_ratio,
        'value_ratio': val_ratio,
        'shift_uniformity': shift_uniformity,
        'saturated_pixels': np.sum(saturated_mask),
        'quadrant_shifts': quadrant_shifts,
        'orig_hue_mean': orig_hue_mean * 360,  # Convert to degrees for feedback
        'result_hue_mean': result_hue_mean * 360
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size
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
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed significantly
    }


def check_hue_shift(traj, env_info, task_info):
    """
    Main verifier function for hue shift task.
    Checks:
    1. Hue was shifted uniformly by 20-170 degrees
    2. Saturation values remain within 90-110% of original
    3. Value (brightness) values remain within 90-110% of original
    4. Shift is uniform across different image regions
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
        "/home/ga/Desktop/hue_shifted.jpg",
        "/home/ga/Desktop/hue_shifted.png",
        "/home/ga/Desktop/hue_shifted.jpeg",
        "/home/ga/Desktop/colorful_hue_shifted.jpg",
        "/home/ga/Desktop/colorful_image_shifted.jpg"
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
        
        # Analyze hue shift
        hue_analysis = analyze_hue_shift(original_image, result_image)
        
        if 'error' in hue_analysis:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Analysis error: {hue_analysis['error']}"
            }
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original hue mean: {hue_analysis['orig_hue_mean']:.1f}°")
        feedback_parts.append(f"Result hue mean: {hue_analysis['result_hue_mean']:.1f}°")
        feedback_parts.append(f"Hue shift: {hue_analysis['hue_shift_degrees']:.1f}°")
        feedback_parts.append(f"Saturation ratio: {hue_analysis['saturation_ratio']:.2f}")
        feedback_parts.append(f"Value ratio: {hue_analysis['value_ratio']:.2f}")
        feedback_parts.append(f"Shift uniformity (std): {hue_analysis['shift_uniformity']:.1f}°")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant hue shift (20-170 degrees)
        hue_shift_significant = 20 <= hue_analysis['hue_shift_degrees'] <= 170
        if hue_shift_significant:
            criteria_met += 1
        feedback_parts.append(f"Significant hue shift (20-170°): {'✅' if hue_shift_significant else '❌'}")
        
        # 2. Saturation preserved (90-110% of original)
        saturation_preserved = 0.9 <= hue_analysis['saturation_ratio'] <= 1.1
        if saturation_preserved:
            criteria_met += 1
        feedback_parts.append(f"Saturation preserved (90-110%): {'✅' if saturation_preserved else '❌'}")
        
        # 3. Value/brightness preserved (90-110% of original)
        value_preserved = 0.9 <= hue_analysis['value_ratio'] <= 1.1
        if value_preserved:
            criteria_met += 1
        feedback_parts.append(f"Value preserved (90-110%): {'✅' if value_preserved else '❌'}")
        
        # 4. Uniform shift (standard deviation < 30 degrees across regions)
        uniform_shift = hue_analysis['shift_uniformity'] < 30
        if uniform_shift:
            criteria_met += 1
        feedback_parts.append(f"Uniform shift (std <30°): {'✅' if uniform_shift else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent uniform hue shift!")
        elif passed:
            feedback_parts.append("✅ Good uniform hue shift!")
        else:
            feedback_parts.append("❌ Hue shift needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in hue shift verification: {e}")
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
    result = check_hue_shift([], {}, {})
    print(f"Test result: {result}")