#!/usr/bin/env python3
"""
Verifier for GIMP saturation enhancement task.
Checks if image saturation was appropriately enhanced using HSV color space analysis.
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


def rgb_to_hsv_array(img):
    """
    Convert RGB image to HSV color space.
    Returns HSV array with H, S, V in ranges [0-360], [0-255], [0-255]
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    rgb_array = np.array(img)
    height, width, channels = rgb_array.shape
    
    # Normalize RGB to [0,1] for colorsys
    rgb_norm = rgb_array / 255.0
    
    # Convert each pixel from RGB to HSV
    hsv_array = np.zeros_like(rgb_norm)
    
    for i in range(height):
        for j in range(width):
            r, g, b = rgb_norm[i, j]
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            # Convert to our desired ranges
            hsv_array[i, j] = [h * 360, s * 255, v * 255]
    
    return hsv_array.astype(np.float32)


def analyze_saturation_enhancement(original_img, result_img):
    """
    Analyze saturation changes between original and enhanced images using HSV color space.
    """
    # Convert to HSV color space
    orig_hsv = rgb_to_hsv_array(original_img)
    result_hsv = rgb_to_hsv_array(result_img)
    
    # Ensure images are same size
    if orig_hsv.shape != result_hsv.shape:
        # Resize result to match original
        result_img_resized = result_img.resize(original_img.size)
        result_hsv = rgb_to_hsv_array(result_img_resized)
    
    # Extract channels
    orig_hue = orig_hsv[:, :, 0]      # Hue [0-360]
    orig_sat = orig_hsv[:, :, 1]      # Saturation [0-255]
    orig_val = orig_hsv[:, :, 2]      # Value [0-255]
    
    result_hue = result_hsv[:, :, 0]
    result_sat = result_hsv[:, :, 1]
    result_val = result_hsv[:, :, 2]
    
    # Calculate enhancement metrics
    mean_orig_sat = np.mean(orig_sat)
    mean_result_sat = np.mean(result_sat)
    saturation_increase = mean_result_sat - mean_orig_sat
    
    # Check hue stability (should remain mostly unchanged)
    hue_difference = np.mean(np.abs(orig_hue - result_hue))
    # Handle circular nature of hue (360° = 0°)
    hue_difference = np.minimum(hue_difference, 360 - hue_difference)
    
    # Check value/brightness stability
    value_difference = np.mean(np.abs(orig_val - result_val))
    
    # Check for over-saturation (pixels reaching maximum saturation)
    oversaturated_pixels = np.sum(result_sat >= 250)  # Near maximum saturation
    total_pixels = result_sat.size
    oversaturation_percentage = (oversaturated_pixels / total_pixels) * 100
    
    return {
        'original_mean_saturation': mean_orig_sat,
        'result_mean_saturation': mean_result_sat,
        'saturation_increase': saturation_increase,
        'hue_stability': hue_difference,
        'value_stability': value_difference,
        'oversaturation_percentage': oversaturation_percentage
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size for comparison
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
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed
    }


def check_saturation_enhancement(traj, env_info, task_info):
    """
    Main verifier function for saturation enhancement task.
    Checks:
    1. Saturation was increased within professional range (+15 to +50 units)
    2. Hue values remained stable (±5 units tolerance)
    3. No excessive over-saturation occurred
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
        "/home/ga/Desktop/enhanced_saturation.jpg",
        "/home/ga/Desktop/enhanced_saturation.png",
        "/home/ga/Desktop/enhanced_saturation.jpeg",
        "/home/ga/Desktop/nature_enhanced.jpg",
        "/home/ga/Desktop/nature_image_enhanced.jpg",
        "/home/ga/Desktop/saturation_enhanced.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/nature_image.jpg",
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
        
        # Analyze saturation enhancement
        enhancement_analysis = analyze_saturation_enhancement(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original saturation: {enhancement_analysis['original_mean_saturation']:.1f}")
        feedback_parts.append(f"Result saturation: {enhancement_analysis['result_mean_saturation']:.1f}")
        feedback_parts.append(f"Saturation increase: {enhancement_analysis['saturation_increase']:.1f}")
        feedback_parts.append(f"Hue stability: {enhancement_analysis['hue_stability']:.1f}°")
        feedback_parts.append(f"Value stability: {enhancement_analysis['value_stability']:.1f}")
        feedback_parts.append(f"Over-saturation: {enhancement_analysis['oversaturation_percentage']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Saturation increased within professional range (+15 to +50 units)
        good_enhancement = 15 <= enhancement_analysis['saturation_increase'] <= 50
        if good_enhancement:
            criteria_met += 1
        feedback_parts.append(f"Saturation enhanced (+15 to +50): {'✅' if good_enhancement else '❌'}")
        
        # 2. Hue values remained stable (±5 units tolerance)
        stable_hues = enhancement_analysis['hue_stability'] <= 5
        if stable_hues:
            criteria_met += 1
        feedback_parts.append(f"Hue preserved (≤5° change): {'✅' if stable_hues else '❌'}")
        
        # 3. No excessive over-saturation (≤5% of pixels oversaturated)
        no_oversaturation = enhancement_analysis['oversaturation_percentage'] <= 5
        if no_oversaturation:
            criteria_met += 1
        feedback_parts.append(f"No over-processing (≤5% oversaturated): {'✅' if no_oversaturation else '❌'}")
        
        # 4. Brightness/value remained relatively stable
        stable_brightness = enhancement_analysis['value_stability'] <= 15
        if stable_brightness:
            criteria_met += 1
        feedback_parts.append(f"Brightness preserved (≤15 change): {'✅' if stable_brightness else '❌'}")
        
        # 5. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (rounded up from 3.75)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent saturation enhancement!")
        elif passed:
            feedback_parts.append("✅ Good saturation enhancement!")
        else:
            feedback_parts.append("❌ Saturation enhancement needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in saturation enhancement verification: {e}")
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
    result = check_saturation_enhancement([], {}, {})
    print(f"Test result: {result}")