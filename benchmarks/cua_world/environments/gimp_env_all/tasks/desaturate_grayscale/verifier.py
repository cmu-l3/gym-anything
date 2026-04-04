#!/usr/bin/env python3
"""
Verifier for GIMP desaturate to grayscale task.
Checks if image was successfully converted to grayscale (black and white).
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


def check_grayscale_property(img, tolerance=2):
    """
    Check if image has grayscale property (R≈G≈B for each pixel).
    Returns percentage of pixels that satisfy grayscale property.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    r, g, b = img_array[:,:,0], img_array[:,:,1], img_array[:,:,2]
    
    # Check if R≈G≈B for each pixel (within tolerance)
    rg_diff = np.abs(r.astype(np.int16) - g.astype(np.int16))
    gb_diff = np.abs(g.astype(np.int16) - b.astype(np.int16))
    rb_diff = np.abs(r.astype(np.int16) - b.astype(np.int16))
    
    grayscale_mask = (rg_diff <= tolerance) & (gb_diff <= tolerance) & (rb_diff <= tolerance)
    grayscale_percentage = np.sum(grayscale_mask) / grayscale_mask.size
    
    return grayscale_percentage, {
        'max_rg_diff': np.max(rg_diff),
        'max_gb_diff': np.max(gb_diff),
        'max_rb_diff': np.max(rb_diff),
        'mean_rg_diff': np.mean(rg_diff),
        'mean_gb_diff': np.mean(gb_diff),
        'mean_rb_diff': np.mean(rb_diff)
    }


def analyze_saturation_hsv(img):
    """
    Analyze image saturation using HSV color space.
    Returns saturation metrics for grayscale verification.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    
    # Convert RGB to HSV for each pixel
    hsv_array = np.zeros_like(img_array, dtype=np.float32)
    
    for y in range(height):
        for x in range(width):
            r, g, b = img_array[y, x] / 255.0  # Normalize to 0-1
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            hsv_array[y, x] = [h * 360, s, v]  # H in degrees, S and V in 0-1
    
    saturation_channel = hsv_array[:, :, 1]  # Extract saturation channel
    
    # Calculate saturation metrics
    mean_saturation = np.mean(saturation_channel)
    max_saturation = np.max(saturation_channel)
    low_saturation_pixels = np.sum(saturation_channel <= 0.05)  # Pixels with saturation ≤ 5%
    low_saturation_percentage = low_saturation_pixels / saturation_channel.size
    
    return {
        'mean_saturation': mean_saturation,
        'max_saturation': max_saturation,
        'low_saturation_percentage': low_saturation_percentage,
        'saturation_std': np.std(saturation_channel)
    }


def check_image_modification(original_img, result_img):
    """Check if the image was meaningfully modified."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        if original_img.mode == 'RGB':
            result_img = result_img.convert('RGB')
        else:
            original_img = original_img.convert('RGB')
            result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_difference = np.mean(diff)
    max_difference = np.max(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_change_threshold = 10  # Pixels with >10 intensity change
    if len(diff.shape) == 3:  # RGB image
        pixel_changes = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        pixel_changes = diff
    
    significantly_changed_pixels = np.sum(pixel_changes > significant_change_threshold)
    change_percentage = (significantly_changed_pixels / pixel_changes.size) * 100
    
    return {
        'mean_difference': mean_difference,
        'max_difference': max_difference,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 5  # At least 5% of pixels changed
    }


def check_desaturate_grayscale(traj, env_info, task_info):
    """
    Main verifier function for desaturate to grayscale task.
    Checks:
    1. Image has grayscale property (R≈G≈B for most pixels)
    2. Low saturation in HSV color space
    3. Image was meaningfully modified from original
    4. Dimensions preserved
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
        "/home/ga/Desktop/grayscale_result.jpg",
        "/home/ga/Desktop/grayscale_result.png",
        "/home/ga/Desktop/grayscale_result.jpeg",
        "/home/ga/Desktop/colorful_image_grayscale.jpg",
        "/home/ga/Desktop/colorful_image_desaturated.jpg",
        "/home/ga/Desktop/colorful_image_bw.jpg"
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
        
        # Perform grayscale verification checks
        grayscale_percentage, channel_stats = check_grayscale_property(result_image, tolerance=2)
        saturation_metrics = analyze_saturation_hsv(result_image)
        modification_check = check_image_modification(original_image, result_image)
        dimensions_preserved = (original_image.size == result_image.size)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Grayscale pixels: {grayscale_percentage*100:.1f}%")
        feedback_parts.append(f"Mean saturation: {saturation_metrics['mean_saturation']:.3f}")
        feedback_parts.append(f"Low saturation pixels: {saturation_metrics['low_saturation_percentage']*100:.1f}%")
        feedback_parts.append(f"Pixels changed: {modification_check['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Grayscale property: ≥95% of pixels have R≈G≈B
        grayscale_property_good = grayscale_percentage >= 0.95
        if grayscale_property_good:
            criteria_met += 1
        feedback_parts.append(f"Grayscale property (≥95%): {'✅' if grayscale_property_good else '❌'}")
        
        # 2. Low saturation: mean ≤0.02 and ≥95% pixels with saturation ≤0.05
        saturation_good = (saturation_metrics['mean_saturation'] <= 0.02 and 
                          saturation_metrics['low_saturation_percentage'] >= 0.95)
        if saturation_good:
            criteria_met += 1
        feedback_parts.append(f"Low saturation: {'✅' if saturation_good else '❌'}")
        
        # 3. Image was meaningfully modified
        if modification_check['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_check['meaningfully_changed'] else '❌'}")
        
        # 4. Dimensions preserved
        if dimensions_preserved:
            criteria_met += 1
        feedback_parts.append(f"Dimensions preserved: {'✅' if dimensions_preserved else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect grayscale conversion!")
        elif passed:
            feedback_parts.append("✅ Good grayscale conversion!")
        else:
            feedback_parts.append("❌ Grayscale conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in desaturate grayscale verification: {e}")
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
    result = check_desaturate_grayscale([], {}, {})
    print(f"Test result: {result}")