#!/usr/bin/env python3
"""
Verifier for GIMP colorize task.
Checks if image was colorized with sepia tone (hue uniformity + target hue).
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


def rgb_to_hsv_manual(rgb_array):
    """
    Convert RGB to HSV manually when colorsys/cv2 not available.
    Returns hue in degrees (0-360), saturation and value in 0-1 range.
    """
    rgb_array = rgb_array.astype(np.float32) / 255.0
    r, g, b = rgb_array[..., 0], rgb_array[..., 1], rgb_array[..., 2]
    
    max_val = np.maximum.reduce([r, g, b])
    min_val = np.minimum.reduce([r, g, b])
    delta = max_val - min_val
    
    # Value channel
    v = max_val
    
    # Saturation channel
    s = np.where(max_val == 0, 0, delta / max_val)
    
    # Hue channel
    h = np.zeros_like(max_val)
    
    # Red is max
    idx = (max_val == r) & (delta != 0)
    h[idx] = (60 * ((g[idx] - b[idx]) / delta[idx]) + 360) % 360
    
    # Green is max
    idx = (max_val == g) & (delta != 0)
    h[idx] = (60 * ((b[idx] - r[idx]) / delta[idx]) + 120) % 360
    
    # Blue is max
    idx = (max_val == b) & (delta != 0)
    h[idx] = (60 * ((r[idx] - g[idx]) / delta[idx]) + 240) % 360
    
    return h, s, v


def analyze_colorization(original_img, result_img, target_hue=30):
    """
    Analyze if image was properly colorized with target hue.
    Returns dict with analysis results.
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
    
    # Convert result to HSV for analysis
    try:
        # Try using OpenCV if available
        import cv2
        result_hsv = cv2.cvtColor(result_array, cv2.COLOR_RGB2HSV)
        hue = result_hsv[:, :, 0].astype(np.float32) * 2  # OpenCV uses 0-179, convert to 0-358
        saturation = result_hsv[:, :, 1].astype(np.float32) / 255.0
        value = result_hsv[:, :, 2].astype(np.float32) / 255.0
    except ImportError:
        # Fallback to manual conversion
        hue, saturation, value = rgb_to_hsv_manual(result_array)
    
    # Create mask for reliable hue analysis (exclude very dark/bright/unsaturated pixels)
    valid_mask = (saturation > 0.1) & (value > 0.1) & (value < 0.9)
    
    if np.sum(valid_mask) < 100:  # Not enough valid pixels
        return {
            'hue_uniformity': False,
            'target_hue_match': False,
            'saturation_present': False,
            'luminosity_preserved': False,
            'error': 'Insufficient valid pixels for analysis'
        }
    
    valid_hues = hue[valid_mask]
    valid_sats = saturation[valid_mask]
    valid_values = value[valid_mask]
    
    # 1. Check hue uniformity (monochromatic signature)
    hue_std = np.std(valid_hues)
    hue_uniform = hue_std < 20.0  # Less than 20° standard deviation
    
    # 2. Check target hue match
    median_hue = np.median(valid_hues)
    
    # Calculate circular distance for hue
    hue_error = min(abs(median_hue - target_hue), 
                    360 - abs(median_hue - target_hue))
    target_match = hue_error < 20.0  # Within 20° of target
    
    # 3. Check saturation presence (not grayscale)
    mean_saturation = np.mean(valid_sats)
    has_saturation = mean_saturation > 0.2
    
    # 4. Check luminosity preservation
    # Convert original to grayscale and compare with result value channel
    orig_gray = np.array(original_img.convert('L')).astype(np.float32) / 255.0
    result_value_scaled = (value * 255).astype(np.uint8)
    
    # Calculate correlation between original brightness and result brightness
    orig_flat = orig_gray.flatten()
    result_flat = result_value_scaled.flatten().astype(np.float32) / 255.0
    
    correlation = np.corrcoef(orig_flat, result_flat)[0, 1]
    luminosity_preserved = correlation > 0.85
    
    return {
        'hue_uniformity': hue_uniform,
        'target_hue_match': target_match,
        'saturation_present': has_saturation,
        'luminosity_preserved': luminosity_preserved,
        'hue_std': hue_std,
        'median_hue': median_hue,
        'hue_error': hue_error,
        'mean_saturation': mean_saturation,
        'luminosity_correlation': correlation
    }


def check_colorize(traj, env_info, task_info):
    """
    Main verifier function for colorize task.
    Checks:
    1. Hue uniformity (monochromatic signature)
    2. Target hue achieved (sepia ~30°)
    3. Saturation present (not grayscale)
    4. Luminosity preserved (original brightness relationships maintained)
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
        "/home/ga/Desktop/colorized_sepia.jpg",
        "/home/ga/Desktop/colorized_sepia.png", 
        "/home/ga/Desktop/colorized_sepia.jpeg",
        "/home/ga/Desktop/sepia.jpg",
        "/home/ga/Desktop/landscape_color_colorized.jpg",
        "/home/ga/Desktop/landscape_sepia.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_color.jpg",
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
        
        # Analyze colorization
        analysis = analyze_colorization(original_image, result_image, target_hue=30)
        
        if 'error' in analysis:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Analysis error: {analysis['error']}"
            }
        
        # Check if image was modified (simple comparison)
        images_different = not np.array_equal(np.array(original_image), 
                                            np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Hue std dev: {analysis['hue_std']:.1f}°")
        feedback_parts.append(f"Median hue: {analysis['median_hue']:.1f}°")
        feedback_parts.append(f"Hue error from target: {analysis['hue_error']:.1f}°")
        feedback_parts.append(f"Mean saturation: {analysis['mean_saturation']:.2f}")
        feedback_parts.append(f"Luminosity correlation: {analysis['luminosity_correlation']:.3f}")
        
        feedback_parts.append(f"Hue uniformity: {'✅' if analysis['hue_uniformity'] else '❌'}")
        feedback_parts.append(f"Target hue match: {'✅' if analysis['target_hue_match'] else '❌'}")
        feedback_parts.append(f"Saturation present: {'✅' if analysis['saturation_present'] else '❌'}")
        feedback_parts.append(f"Luminosity preserved: {'✅' if analysis['luminosity_preserved'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on 4 main criteria
        criteria_met = 0
        total_criteria = 4
        
        if analysis['hue_uniformity']:
            criteria_met += 1
        if analysis['target_hue_match']:
            criteria_met += 1 
        if analysis['saturation_present']:
            criteria_met += 1
        if analysis['luminosity_preserved']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect sepia colorization!")
        elif passed:
            feedback_parts.append("✅ Good sepia colorization!")
        else:
            feedback_parts.append("❌ Colorization needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in colorize verification: {e}")
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
    result = check_colorize([], {}, {})
    print(f"Test result: {result}")