#!/usr/bin/env python3
"""
Verifier for GIMP grayscale mode conversion task.
Checks if image was converted from RGB mode to true Grayscale mode.
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


def check_image_mode_properties(img):
    """
    Check properties of an image to determine its mode characteristics.
    Returns detailed information about channels, mode, and color properties.
    """
    mode = img.mode
    bands = img.getbands()
    n_channels = len(bands)
    
    properties = {
        'mode': mode,
        'bands': bands,
        'n_channels': n_channels,
        'is_grayscale': mode == 'L',
        'is_rgb': mode == 'RGB',
        'is_rgba': mode == 'RGBA',
        'size': img.size
    }
    
    return properties


def verify_grayscale_conversion(original_img, result_img):
    """
    Verify that the result image is a proper grayscale conversion of the original.
    Checks mode, channel count, and pixel properties.
    """
    orig_props = check_image_mode_properties(original_img)
    result_props = check_image_mode_properties(result_img)
    
    # Check 1: Result should be in Grayscale mode ('L')
    is_grayscale_mode = result_props['is_grayscale']
    
    # Check 2: Original should have been RGB (to verify actual conversion occurred)
    was_rgb_originally = orig_props['is_rgb'] or orig_props['is_rgba']
    
    # Check 3: If result is converted back to RGB, all channels should be identical
    r_g_b_identical = False
    if result_props['is_grayscale']:
        result_as_rgb = result_img.convert('RGB')
        r, g, b = result_as_rgb.split()
        r_arr, g_arr, b_arr = np.array(r), np.array(g), np.array(b)
        r_g_b_identical = np.array_equal(r_arr, g_arr) and np.array_equal(g_arr, b_arr)
    
    # Check 4: Compare luminance preservation
    correlation = 0.0
    if original_img.size == result_img.size:
        # Convert original to grayscale for comparison
        orig_gray = original_img.convert('L')
        orig_arr = np.array(orig_gray)
        result_arr = np.array(result_img)
        
        # Calculate correlation between original and result luminance
        if orig_arr.size > 0 and result_arr.size > 0:
            correlation = np.corrcoef(orig_arr.flatten(), result_arr.flatten())[0, 1]
    
    return {
        'is_grayscale_mode': is_grayscale_mode,
        'was_rgb_originally': was_rgb_originally,
        'r_g_b_identical': r_g_b_identical,
        'luminance_correlation': correlation,
        'tonal_preservation_good': correlation >= 0.95,
        'original_properties': orig_props,
        'result_properties': result_props
    }


def check_meaningful_mode_change(original_img, result_img):
    """Check if the image mode was actually changed (not just appearance)."""
    orig_props = check_image_mode_properties(original_img)
    result_props = check_image_mode_properties(result_img)
    
    # True mode change: RGB/RGBA -> Grayscale
    mode_changed = (orig_props['is_rgb'] or orig_props['is_rgba']) and result_props['is_grayscale']
    
    # Channel count should have decreased
    channel_count_decreased = result_props['n_channels'] < orig_props['n_channels']
    
    return {
        'mode_changed': mode_changed,
        'channel_count_decreased': channel_count_decreased,
        'original_mode': orig_props['mode'],
        'result_mode': result_props['mode'],
        'original_channels': orig_props['n_channels'],
        'result_channels': result_props['n_channels']
    }


def check_grayscale_mode(traj, env_info, task_info):
    """
    Main verifier function for grayscale mode conversion task.
    Checks:
    1. Image was converted to true Grayscale mode (single channel, mode='L')
    2. Result has R=G=B properties when converted to RGB
    3. Tonal information was preserved during conversion
    4. Mode was actually changed from RGB to Grayscale
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
        "/home/ga/Desktop/grayscale_mode.jpg",
        "/home/ga/Desktop/grayscale_mode.png", 
        "/home/ga/Desktop/grayscale_mode.jpeg",
        "/home/ga/Desktop/color_image_grayscale.jpg",
        "/home/ga/Desktop/color_image_gray.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/color_image.jpg",
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
        
        # Verify grayscale conversion
        conversion_analysis = verify_grayscale_conversion(original_image, result_image)
        
        # Check mode change
        mode_change_analysis = check_meaningful_mode_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original: {conversion_analysis['original_properties']['mode']} mode, {conversion_analysis['original_properties']['n_channels']} channels")
        feedback_parts.append(f"Result: {conversion_analysis['result_properties']['mode']} mode, {conversion_analysis['result_properties']['n_channels']} channels")
        feedback_parts.append(f"True Grayscale mode: {'✅' if conversion_analysis['is_grayscale_mode'] else '❌'}")
        feedback_parts.append(f"R=G=B pixels: {'✅' if conversion_analysis['r_g_b_identical'] else '❌'}")
        feedback_parts.append(f"Tonal preservation: {'✅' if conversion_analysis['tonal_preservation_good'] else '❌'} (corr={conversion_analysis['luminance_correlation']:.3f})")
        feedback_parts.append(f"Mode changed: {'✅' if mode_change_analysis['mode_changed'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if conversion_analysis['is_grayscale_mode']:
            criteria_met += 1
        if conversion_analysis['r_g_b_identical']:
            criteria_met += 1
        if conversion_analysis['tonal_preservation_good']:
            criteria_met += 1
        if mode_change_analysis['mode_changed']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect grayscale mode conversion!")
        elif passed:
            feedback_parts.append("✅ Good grayscale mode conversion!")
        else:
            feedback_parts.append("❌ Grayscale mode conversion failed or incomplete")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in grayscale mode verification: {e}")
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
    result = check_grayscale_mode([], {}, {})
    print(f"Test result: {result}")