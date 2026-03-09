#!/usr/bin/env python3
"""
Verifier for GIMP shadows-highlights adjustment task.
Checks if shadow areas were brightened and tonal balance improved.
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


def rgb_to_luminance(img):
    """Convert RGB image to luminance using perceptual weighting (ITU-R BT.601)."""
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    # Perceptual luminance weights: 0.299*R + 0.587*G + 0.114*B
    luminance = np.dot(img_array, [0.299, 0.587, 0.114])
    return luminance


def analyze_shadow_recovery(original_img, result_img):
    """
    Analyze shadow recovery by comparing luminance distributions.
    """
    # Convert images to luminance
    original_lum = rgb_to_luminance(original_img)
    result_lum = rgb_to_luminance(result_img)
    
    # Ensure same size for comparison
    if original_lum.shape != result_lum.shape:
        # Resize result to match original
        result_img_resized = result_img.resize(original_img.size)
        result_lum = rgb_to_luminance(result_img_resized)
    
    # Calculate histogram percentiles
    original_percentiles = {
        '10th': np.percentile(original_lum, 10),
        '25th': np.percentile(original_lum, 25),
        '50th': np.percentile(original_lum, 50),
        'mean': np.mean(original_lum)
    }
    
    result_percentiles = {
        '10th': np.percentile(result_lum, 10),
        '25th': np.percentile(result_lum, 25), 
        '50th': np.percentile(result_lum, 50),
        'mean': np.mean(result_lum)
    }
    
    # Define shadow regions (bottom 25% of luminance)
    shadow_threshold = original_percentiles['25th']
    original_shadows = original_lum[original_lum <= shadow_threshold]
    result_shadows = result_lum[result_lum <= shadow_threshold * 1.2]  # Allow slight threshold adjustment
    
    # Calculate shadow brightness changes
    original_shadow_mean = np.mean(original_shadows) if len(original_shadows) > 0 else 0
    result_shadow_mean = np.mean(result_shadows) if len(result_shadows) > 0 else 0
    
    shadow_brightness_increase = ((result_shadow_mean - original_shadow_mean) / max(original_shadow_mean, 1)) * 100
    
    # Count very dark pixels (luminance < 20)
    very_dark_original = np.sum(original_lum < 20)
    very_dark_result = np.sum(result_lum < 20)
    total_pixels = original_lum.size
    
    very_dark_reduction = ((very_dark_original - very_dark_result) / max(very_dark_original, 1)) * 100
    
    # Calculate percentile improvements
    percentile_10_increase = result_percentiles['10th'] - original_percentiles['10th']
    percentile_25_increase = result_percentiles['25th'] - original_percentiles['25th']
    
    return {
        'shadow_brightness_increase': shadow_brightness_increase,
        'very_dark_reduction': very_dark_reduction,
        'percentile_10_increase': percentile_10_increase,
        'percentile_25_increase': percentile_25_increase,
        'original_shadow_mean': original_shadow_mean,
        'result_shadow_mean': result_shadow_mean,
        'very_dark_original_pct': (very_dark_original / total_pixels) * 100,
        'very_dark_result_pct': (very_dark_result / total_pixels) * 100
    }


def check_meaningful_tonal_change(original_img, result_img):
    """Check if the images have meaningful tonal differences."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    original_lum = rgb_to_luminance(original_img)
    result_lum = rgb_to_luminance(result_img)
    
    # Calculate pixel-wise difference
    diff = np.abs(original_lum - result_lum)
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(diff > 5)  # Pixels with >5 luminance change
    total_pixels = original_lum.size
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_luminance_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed
    }


def check_shadows_highlights(traj, env_info, task_info):
    """
    Main verifier function for shadows-highlights adjustment task.
    Checks:
    1. Shadow brightness increased by at least 10%
    2. Very dark pixels reduced by at least 25%
    3. 10th and 25th percentile luminance values increased
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
        "/home/ga/Desktop/shadows_highlights_adjusted.jpg",
        "/home/ga/Desktop/shadows_highlights_adjusted.png",
        "/home/ga/Desktop/shadows_highlights_adjusted.jpeg",
        "/home/ga/Desktop/adjusted.jpg",
        "/home/ga/Desktop/high_contrast_adjusted.jpg",
        "/home/ga/Desktop/high_contrast_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/high_contrast_image.jpg",
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
        
        # Analyze shadow recovery
        shadow_analysis = analyze_shadow_recovery(original_image, result_image)
        
        # Check for meaningful tonal change
        change_analysis = check_meaningful_tonal_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Shadow brightness increase: {shadow_analysis['shadow_brightness_increase']:.1f}%")
        feedback_parts.append(f"Very dark pixel reduction: {shadow_analysis['very_dark_reduction']:.1f}%")
        feedback_parts.append(f"10th percentile increase: {shadow_analysis['percentile_10_increase']:.1f}")
        feedback_parts.append(f"25th percentile increase: {shadow_analysis['percentile_25_increase']:.1f}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Shadow brightness increased by at least 10%
        shadow_brightening_good = shadow_analysis['shadow_brightness_increase'] >= 10.0
        if shadow_brightening_good:
            criteria_met += 1
        feedback_parts.append(f"Shadow brightening (≥10%): {'✅' if shadow_brightening_good else '❌'}")
        
        # 2. Very dark pixels reduced by at least 25%
        dark_pixel_reduction_good = shadow_analysis['very_dark_reduction'] >= 25.0
        if dark_pixel_reduction_good:
            criteria_met += 1
        feedback_parts.append(f"Dark pixel reduction (≥25%): {'✅' if dark_pixel_reduction_good else '❌'}")
        
        # 3. Histogram improvement (both 10th and 25th percentiles increased)
        histogram_improved = (shadow_analysis['percentile_10_increase'] > 0 and 
                            shadow_analysis['percentile_25_increase'] > 0)
        if histogram_improved:
            criteria_met += 1
        feedback_parts.append(f"Histogram improvement: {'✅' if histogram_improved else '❌'}")
        
        # 4. Meaningful tonal change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent shadows-highlights adjustment!")
        elif passed:
            feedback_parts.append("✅ Good shadows-highlights adjustment!")
        else:
            feedback_parts.append("❌ Shadows-highlights adjustment needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in shadows-highlights verification: {e}")
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
    result = check_shadows_highlights([], {}, {})
    print(f"Test result: {result}")