#!/usr/bin/env python3
"""
Verifier for GIMP desaturate to black and white task.
Checks if color image was successfully converted to proper grayscale.
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


def check_rgb_channel_equality(img, tolerance=2.0):
    """
    Check if RGB channels are approximately equal (true grayscale).
    Returns mean absolute difference between channels.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    r, g, b = img_array[:,:,0], img_array[:,:,1], img_array[:,:,2]
    
    # Calculate mean absolute differences between channels
    rg_diff = np.abs(r.astype(np.float32) - g.astype(np.float32))
    rb_diff = np.abs(r.astype(np.float32) - b.astype(np.float32))
    gb_diff = np.abs(g.astype(np.float32) - b.astype(np.float32))
    
    mean_channel_diff = (np.mean(rg_diff) + np.mean(rb_diff) + np.mean(gb_diff)) / 3.0
    
    is_grayscale = mean_channel_diff <= tolerance
    
    return is_grayscale, mean_channel_diff


def check_saturation_levels(img, saturation_threshold=0.05, percentage_threshold=0.95):
    """
    Check if image has very low saturation values (desaturated).
    """
    if img.mode != 'HSV':
        hsv_img = img.convert('HSV')
    else:
        hsv_img = img
    
    hsv_array = np.array(hsv_img)
    saturation = hsv_array[:,:,1] / 255.0  # Normalize to 0-1 range
    
    # Count pixels with low saturation
    low_saturation_pixels = np.sum(saturation < saturation_threshold)
    total_pixels = saturation.size
    low_saturation_ratio = low_saturation_pixels / total_pixels
    
    is_desaturated = low_saturation_ratio >= percentage_threshold
    
    return is_desaturated, low_saturation_ratio, np.mean(saturation)


def analyze_tonal_preservation(original_img, result_img, detail_threshold=0.6):
    """
    Analyze if detail and tonal variation were preserved during conversion.
    """
    # Convert result to grayscale for analysis
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Calculate luminosity of original image (weighted RGB to grayscale)
    if original_img.mode != 'RGB':
        original_rgb = original_img.convert('RGB')
    else:
        original_rgb = original_img
    
    orig_array = np.array(original_rgb)
    # Standard luminosity formula: 0.299*R + 0.587*G + 0.114*B
    orig_luminosity = 0.299*orig_array[:,:,0] + 0.587*orig_array[:,:,1] + 0.114*orig_array[:,:,2]
    
    result_array = np.array(result_gray)
    
    # Calculate standard deviations (measure of detail/contrast)
    orig_std = np.std(orig_luminosity)
    result_std = np.std(result_array)
    
    # Detail preservation ratio
    detail_ratio = result_std / max(orig_std, 1.0)  # Avoid division by zero
    detail_preserved = detail_ratio >= detail_threshold
    
    return detail_preserved, detail_ratio, orig_std, result_std


def check_tonal_range(img, min_std_threshold=15.0):
    """
    Check if image has meaningful tonal variation (not flat gray).
    """
    if img.mode != 'L':
        gray_img = img.convert('L')
    else:
        gray_img = img
    
    img_array = np.array(gray_img)
    std_dev = np.std(img_array)
    
    has_variation = std_dev >= min_std_threshold
    
    return has_variation, std_dev


def check_desaturate_bw(traj, env_info, task_info):
    """
    Main verifier function for desaturate to black and white task.
    Checks:
    1. RGB channels are approximately equal (true grayscale)
    2. Saturation values are very low (properly desaturated)
    3. Detail and contrast preserved from original
    4. Image has meaningful tonal variation (not flat gray)
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
        "/home/ga/Desktop/desaturated_bw.jpg",
        "/home/ga/Desktop/desaturated_bw.png",
        "/home/ga/Desktop/desaturated_bw.jpeg",
        "/home/ga/Desktop/colorful_image_desaturated.jpg",
        "/home/ga/Desktop/bw_image.jpg"
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
        
        # 1. Check if RGB channels are equal (true grayscale)
        is_grayscale, mean_channel_diff = check_rgb_channel_equality(result_image, tolerance=2.0)
        
        # 2. Check saturation levels
        is_desaturated, low_sat_ratio, mean_saturation = check_saturation_levels(result_image)
        
        # 3. Check detail preservation
        detail_preserved, detail_ratio, orig_std, result_std = analyze_tonal_preservation(original_image, result_image)
        
        # 4. Check tonal variation
        has_variation, tonal_std = check_tonal_range(result_image, min_std_threshold=15.0)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size or not np.array_equal(
            np.array(original_image.convert('RGB')), 
            np.array(result_image.convert('RGB'))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Mean channel difference: {mean_channel_diff:.2f}")
        feedback_parts.append(f"Low saturation ratio: {low_sat_ratio:.2f}")
        feedback_parts.append(f"Mean saturation: {mean_saturation:.3f}")
        feedback_parts.append(f"Detail preservation ratio: {detail_ratio:.2f}")
        feedback_parts.append(f"Tonal standard deviation: {tonal_std:.1f}")
        feedback_parts.append(f"True grayscale (RGB equal): {'✅' if is_grayscale else '❌'}")
        feedback_parts.append(f"High desaturation: {'✅' if is_desaturated else '❌'}")
        feedback_parts.append(f"Detail preserved: {'✅' if detail_preserved else '❌'}")
        feedback_parts.append(f"Meaningful tonal range: {'✅' if has_variation else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if is_grayscale:
            criteria_met += 1
        if is_desaturated:
            criteria_met += 1
        if detail_preserved:
            criteria_met += 1
        if has_variation:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect black and white conversion!")
        elif passed:
            feedback_parts.append("✅ Good desaturation to black and white!")
        else:
            feedback_parts.append("❌ Desaturation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in desaturate verification: {e}")
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
    result = check_desaturate_bw([], {}, {})
    print(f"Test result: {result}")