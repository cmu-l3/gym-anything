#!/usr/bin/env python3
"""
Verifier for GIMP desaturate task.
Checks if a color image was successfully converted to grayscale.
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


def analyze_grayscale_conversion(original_img, result_img):
    """
    Comprehensive analysis to verify grayscale conversion quality.
    Uses multiple methods: channel correlation, HSV saturation, and hue variance.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    
    # 1. RGB Channel Correlation Analysis
    # In a grayscale image, R, G, B channels should be nearly identical
    r_channel = result_array[:, :, 0].flatten()
    g_channel = result_array[:, :, 1].flatten()
    b_channel = result_array[:, :, 2].flatten()
    
    # Calculate correlations between channels
    rg_corr = np.corrcoef(r_channel, g_channel)[0, 1] if len(r_channel) > 1 else 1.0
    rb_corr = np.corrcoef(r_channel, b_channel)[0, 1] if len(r_channel) > 1 else 1.0
    gb_corr = np.corrcoef(g_channel, b_channel)[0, 1] if len(g_channel) > 1 else 1.0
    
    # Handle NaN correlations (can happen with constant images)
    correlations = [rg_corr, rb_corr, gb_corr]
    correlations = [c for c in correlations if not np.isnan(c)]
    avg_correlation = np.mean(correlations) if correlations else 1.0
    
    # 2. HSV Saturation Analysis  
    # Convert to HSV and check saturation levels
    hsv_img = result_img.convert('HSV')
    hsv_array = np.array(hsv_img)
    saturation_channel = hsv_array[:, :, 1]  # S channel
    avg_saturation = np.mean(saturation_channel) / 255.0  # Normalize to 0-1
    
    # 3. Hue Variance Analysis
    # Grayscale images should have minimal hue variance
    hue_channel = hsv_array[:, :, 0]
    # Filter out pixels with very low saturation (their hue is meaningless)
    meaningful_hue_pixels = hue_channel[saturation_channel > 10]
    hue_variance = np.var(meaningful_hue_pixels) if len(meaningful_hue_pixels) > 0 else 0
    
    # 4. Color Uniformity Check
    # Check if RGB values are close to each other for most pixels
    rgb_diff = np.abs(result_array[:, :, 0].astype(float) - result_array[:, :, 1].astype(float)) + \
               np.abs(result_array[:, :, 1].astype(float) - result_array[:, :, 2].astype(float)) + \
               np.abs(result_array[:, :, 0].astype(float) - result_array[:, :, 2].astype(float))
    
    avg_rgb_diff = np.mean(rgb_diff)
    
    return {
        'avg_correlation': avg_correlation,
        'avg_saturation': avg_saturation,
        'hue_variance': hue_variance,
        'avg_rgb_diff': avg_rgb_diff,
        'is_grayscale_correlation': avg_correlation >= 0.95,
        'is_grayscale_saturation': avg_saturation <= 0.05,
        'is_grayscale_hue': hue_variance <= 100,
        'is_grayscale_uniformity': avg_rgb_diff <= 15
    }


def detect_meaningful_change(original_img, result_img):
    """Check if the image was meaningfully modified from the original."""
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Calculate pixel differences
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Check if images are identical
    if np.array_equal(orig_array, result_array):
        return False, 0.0
    
    # Calculate percentage of changed pixels
    if len(orig_array.shape) == 3:  # Color image
        pixel_diffs = np.sum(np.abs(orig_array.astype(float) - result_array.astype(float)), axis=2)
    else:  # Grayscale
        pixel_diffs = np.abs(orig_array.astype(float) - result_array.astype(float))
    
    significant_changes = pixel_diffs > 10  # Pixels with >10 intensity change
    change_percentage = np.sum(significant_changes) / significant_changes.size * 100
    
    return change_percentage > 5, change_percentage  # At least 5% of pixels changed


def check_desaturate(traj, env_info, task_info):
    """
    Main verifier function for desaturate task.
    Checks:
    1. Image was converted to proper grayscale (low saturation, high channel correlation)
    2. RGB channels are highly correlated (near identical)
    3. Hue variance is minimal
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
        "/home/ga/Desktop/landscape_grayscale.jpg",
        "/home/ga/Desktop/landscape_grayscale.png", 
        "/home/ga/Desktop/landscape_grayscale.jpeg",
        "/home/ga/Desktop/color_landscape_desaturated.jpg",
        "/home/ga/Desktop/grayscale_landscape.jpg",
        "/home/ga/Desktop/color_landscape_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/color_landscape.jpg",
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
        
        # Analyze grayscale conversion
        grayscale_analysis = analyze_grayscale_conversion(original_image, result_image)
        
        # Check for meaningful change
        changed, change_percentage = detect_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Channel correlation: {grayscale_analysis['avg_correlation']:.3f}")
        feedback_parts.append(f"Average saturation: {grayscale_analysis['avg_saturation']:.3f}")
        feedback_parts.append(f"Hue variance: {grayscale_analysis['hue_variance']:.1f}")
        feedback_parts.append(f"RGB difference: {grayscale_analysis['avg_rgb_diff']:.1f}")
        feedback_parts.append(f"Pixels changed: {change_percentage:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. High channel correlation (R, G, B channels nearly identical)
        if grayscale_analysis['is_grayscale_correlation']:
            criteria_met += 1
        feedback_parts.append(f"Channel correlation ≥0.95: {'✅' if grayscale_analysis['is_grayscale_correlation'] else '❌'}")
        
        # 2. Low saturation (minimal color content)
        if grayscale_analysis['is_grayscale_saturation']:
            criteria_met += 1
        feedback_parts.append(f"Low saturation ≤0.05: {'✅' if grayscale_analysis['is_grayscale_saturation'] else '❌'}")
        
        # 3. Consistent RGB channels (small differences between R,G,B)
        if grayscale_analysis['is_grayscale_uniformity']:
            criteria_met += 1
        feedback_parts.append(f"RGB uniformity ≤15: {'✅' if grayscale_analysis['is_grayscale_uniformity'] else '❌'}")
        
        # 4. Image was modified
        if changed:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if changed else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect grayscale conversion!")
        elif passed:
            feedback_parts.append("✅ Good grayscale conversion!")
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
    result = check_desaturate([], {}, {})
    print(f"Test result: {result}")