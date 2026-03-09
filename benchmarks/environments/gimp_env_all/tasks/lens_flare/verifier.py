#!/usr/bin/env python3
"""
Verifier for GIMP lens flare task.
Checks if a lens flare effect was successfully applied to an outdoor image.
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


def detect_lens_flare(original_img, result_img):
    """
    Detect lens flare by analyzing brightness increases.
    Returns analysis of bright regions that indicate lens flare presence.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for brightness analysis
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Calculate brightness increase (delta)
    brightness_delta = result_array.astype(np.float32) - orig_array.astype(np.float32)
    
    # Identify significantly brighter pixels (likely flare area)
    bright_threshold = 30  # Minimum brightness increase for flare detection
    bright_pixels = brightness_delta > bright_threshold
    bright_pixel_count = np.sum(bright_pixels)
    
    # Check for very bright peak pixels (flare center)
    max_brightness = np.max(result_array)
    has_bright_peak = max_brightness >= 240
    
    # Verify effect is localized (not global brightness increase)
    total_pixels = result_array.shape[0] * result_array.shape[1]
    bright_percentage = bright_pixel_count / total_pixels
    is_localized = bright_percentage < 0.15  # Less than 15% of image should be brightened
    
    # Check position - lens flare typically appears in upper portion of image
    position_appropriate = False
    if bright_pixel_count > 0:
        # Find coordinates of bright pixels
        bright_coords = np.argwhere(bright_pixels)
        if len(bright_coords) > 0:
            # Calculate average Y position of bright pixels
            avg_y_position = np.mean(bright_coords[:, 0])
            # Check if in upper 60% of image (good for sky placement)
            position_appropriate = avg_y_position < (result_array.shape[0] * 0.6)
    
    # Additional analysis: check for brightness clustering
    clustered_effect = False
    if bright_pixel_count >= 200:  # Substantial bright region
        clustered_effect = True
    
    return {
        'bright_pixel_count': int(bright_pixel_count),
        'has_bright_peak': has_bright_peak,
        'is_localized': is_localized,
        'position_appropriate': position_appropriate,
        'clustered_effect': clustered_effect,
        'max_brightness': int(max_brightness),
        'bright_percentage': float(bright_percentage)
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images show meaningful differences indicating lens flare was applied."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert both to RGB for pixel comparison
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference magnitude
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    pixel_diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Count pixels with significant change (>30 intensity units)
    significant_change_pixels = np.sum(pixel_diff_magnitude > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_change_pixels / total_pixels) * 100
    
    # Require at least 2% of pixels to have changed significantly
    meaningful_change = change_percentage >= 2.0
    
    return {
        'change_percentage': change_percentage,
        'meaningful_change': meaningful_change,
        'significant_pixels': int(significant_change_pixels)
    }


def check_lens_flare(traj, env_info, task_info):
    """
    Main verifier function for lens flare task.
    Checks:
    1. Bright regions were added to the image (lens flare effect)
    2. Effect is localized (not global brightness increase)
    3. Flare is positioned appropriately (upper portion)
    4. Image shows meaningful changes from original
    5. Very bright pixels indicate flare center
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
        "/home/ga/Desktop/lens_flare_effect.jpg",
        "/home/ga/Desktop/lens_flare_effect.png",
        "/home/ga/Desktop/lens_flare_effect.jpeg",
        "/home/ga/Desktop/outdoor_scene_flare.jpg",
        "/home/ga/Desktop/flare_effect.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/outdoor_scene.jpg",
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
        
        # Analyze lens flare characteristics
        flare_analysis = detect_lens_flare(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Bright pixels added: {flare_analysis['bright_pixel_count']}")
        feedback_parts.append(f"Max brightness: {flare_analysis['max_brightness']}")
        feedback_parts.append(f"Brightness percentage: {flare_analysis['bright_percentage']:.2f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Significant bright region added (≥200 pixels with >30 intensity increase)
        bright_region_adequate = flare_analysis['bright_pixel_count'] >= 200
        if bright_region_adequate:
            criteria_met += 1
        feedback_parts.append(f"Adequate bright region: {'✅' if bright_region_adequate else '❌'}")
        
        # 2. High intensity peak (≥240 brightness indicating flare center)
        if flare_analysis['has_bright_peak']:
            criteria_met += 1
        feedback_parts.append(f"High intensity peak: {'✅' if flare_analysis['has_bright_peak'] else '❌'}")
        
        # 3. Localized effect (not global brightness increase)
        if flare_analysis['is_localized']:
            criteria_met += 1
        feedback_parts.append(f"Localized effect: {'✅' if flare_analysis['is_localized'] else '❌'}")
        
        # 4. Appropriate positioning (upper portion of image)
        if flare_analysis['position_appropriate']:
            criteria_met += 1
        feedback_parts.append(f"Good positioning: {'✅' if flare_analysis['position_appropriate'] else '❌'}")
        
        # 5. Meaningful change detected (≥2% pixels significantly changed)
        if change_analysis['meaningful_change']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningful_change'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) but allow 75% threshold
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent lens flare effect!")
        elif passed:
            feedback_parts.append("✅ Good lens flare effect applied!")
        else:
            feedback_parts.append("❌ Lens flare effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in lens flare verification: {e}")
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
    result = check_lens_flare([], {}, {})
    print(f"Test result: {result}")