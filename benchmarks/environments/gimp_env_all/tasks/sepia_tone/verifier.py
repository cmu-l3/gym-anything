#!/usr/bin/env python3
"""
Verifier for GIMP sepia tone task.
Checks if color image was successfully converted to vintage sepia tone.
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


def analyze_sepia_characteristics(img):
    """
    Analyze image for sepia tone characteristics.
    Returns metrics about RGB channel relationships, hue range, and saturation.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img).astype(np.float32)
    
    # Extract RGB channels
    r_channel = img_array[:, :, 0]
    g_channel = img_array[:, :, 1]
    b_channel = img_array[:, :, 2]
    
    # Calculate mean values for each channel
    r_mean = np.mean(r_channel)
    g_mean = np.mean(g_channel)
    b_mean = np.mean(b_channel)
    
    # 1. Check RGB channel hierarchy (sepia signature: R > G > B)
    hierarchy_correct = (r_mean > g_mean > b_mean)
    
    # 2. Calculate RGB ratios typical for sepia
    rg_ratio = r_mean / (g_mean + 1e-6)  # Avoid division by zero
    gb_ratio = g_mean / (b_mean + 1e-6)
    
    # Sepia typically shows: R/G ≈ 1.1-1.3, G/B ≈ 1.05-1.2
    ratio_valid = (1.05 < rg_ratio < 1.35) and (1.02 < gb_ratio < 1.25)
    
    # 3. Analyze color temperature (warm = brown/yellow)
    try:
        hsv_img = img.convert('HSV')
        hsv_array = np.array(hsv_img)
        hue_channel = hsv_array[:, :, 0]
        sat_channel = hsv_array[:, :, 1]
        
        # Convert PIL HSV (0-255) to standard HSV (0-360 for hue)
        hue_degrees = (hue_channel.astype(np.float32) / 255.0) * 360.0
        
        # Sepia hues typically in 20-50 degree range (yellow-orange-brown)
        warm_hue_mask = ((hue_degrees >= 20) & (hue_degrees <= 50)) | (hue_degrees == 0)  # Include undefined hue (grayscale areas)
        warm_hue_percentage = np.sum(warm_hue_mask) / hue_channel.size
        
        # Check saturation level (moderate, not zero, not high)
        mean_saturation = np.mean(sat_channel) / 255.0  # Normalize to 0-1
        saturation_appropriate = (0.10 < mean_saturation < 0.50)
        
    except Exception as e:
        logging.warning(f"HSV analysis failed: {e}")
        warm_hue_percentage = 0.5  # Assume neutral
        saturation_appropriate = False
    
    # 4. Check for low color variance (indicating monochromatic base)
    color_variance = np.std([r_channel.std(), g_channel.std(), b_channel.std()])
    low_variance = color_variance < 25  # Indicates consistent color cast
    
    return {
        'hierarchy_correct': hierarchy_correct,
        'ratio_valid': ratio_valid,
        'warm_hue_percentage': warm_hue_percentage,
        'saturation_appropriate': saturation_appropriate,
        'low_variance': low_variance,
        'r_mean': r_mean,
        'g_mean': g_mean,
        'b_mean': b_mean,
        'rg_ratio': rg_ratio,
        'gb_ratio': gb_ratio,
        'mean_saturation': mean_saturation if 'mean_saturation' in locals() else 0
    }


def check_grayscale_base(original_img, result_img):
    """
    Check if the result shows evidence of starting from a grayscale base.
    This indicates proper workflow (desaturate first, then colorize).
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Resize if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    # Calculate color variance in original vs result
    orig_color_var = np.var([orig_array[:,:,0].std(), orig_array[:,:,1].std(), orig_array[:,:,2].std()])
    result_color_var = np.var([result_array[:,:,0].std(), result_array[:,:,1].std(), result_array[:,:,2].std()])
    
    # Result should have lower color variance than original (more monochromatic)
    variance_reduced = result_color_var < orig_color_var * 0.8
    
    # Check if result has the characteristic sepia color relationships
    r_channel = result_array[:, :, 0]
    g_channel = result_array[:, :, 1]
    b_channel = result_array[:, :, 2]
    
    # Calculate correlation between channels (high correlation indicates grayscale base)
    rg_corr = np.corrcoef(r_channel.flatten(), g_channel.flatten())[0, 1]
    rb_corr = np.corrcoef(r_channel.flatten(), b_channel.flatten())[0, 1]
    gb_corr = np.corrcoef(g_channel.flatten(), b_channel.flatten())[0, 1]
    
    high_correlation = (rg_corr > 0.85 and rb_corr > 0.85 and gb_corr > 0.85)
    
    return {
        'variance_reduced': variance_reduced,
        'high_correlation': high_correlation,
        'grayscale_base_likely': variance_reduced and high_correlation
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array - result_array)
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed significantly
    }


def check_sepia_tone(traj, env_info, task_info):
    """
    Main verifier function for sepia tone task.
    Checks:
    1. Image has grayscale base characteristics
    2. RGB channels follow sepia hierarchy (R > G > B)
    3. Hue range is appropriate (warm brown tones)
    4. Saturation is moderate (not gray, not oversaturated)
    5. Image was meaningfully modified
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
        "/home/ga/Desktop/sepia_photo.jpg",
        "/home/ga/Desktop/sepia_photo.png",
        "/home/ga/Desktop/sepia_photo.jpeg",
        "/home/ga/Desktop/color_photo_sepia.jpg",
        "/home/ga/Desktop/photo_sepia.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/color_photo.jpg",
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
        
        # Analyze sepia characteristics
        sepia_analysis = analyze_sepia_characteristics(result_image)
        
        # Check for grayscale base workflow
        grayscale_analysis = check_grayscale_base(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"RGB hierarchy (R>G>B): {'✅' if sepia_analysis['hierarchy_correct'] else '❌'}")
        feedback_parts.append(f"RGB ratios: R/G={sepia_analysis['rg_ratio']:.2f}, G/B={sepia_analysis['gb_ratio']:.2f}")
        feedback_parts.append(f"Valid RGB ratios: {'✅' if sepia_analysis['ratio_valid'] else '❌'}")
        feedback_parts.append(f"Warm hue percentage: {sepia_analysis['warm_hue_percentage']:.1%}")
        feedback_parts.append(f"Appropriate saturation: {'✅' if sepia_analysis['saturation_appropriate'] else '❌'}")
        feedback_parts.append(f"Low color variance: {'✅' if sepia_analysis['low_variance'] else '❌'}")
        feedback_parts.append(f"Grayscale base likely: {'✅' if grayscale_analysis['grayscale_base_likely'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. RGB channel hierarchy correct (sepia signature)
        if sepia_analysis['hierarchy_correct']:
            criteria_met += 1
        
        # 2. RGB ratios in valid range for sepia
        if sepia_analysis['ratio_valid']:
            criteria_met += 1
        
        # 3. Warm hue range (at least 70% of image in warm tones)
        if sepia_analysis['warm_hue_percentage'] >= 0.7:
            criteria_met += 1
        
        # 4. Appropriate saturation level
        if sepia_analysis['saturation_appropriate']:
            criteria_met += 1
        
        # 5. Image meaningfully changed
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent sepia tone conversion!")
        elif passed:
            feedback_parts.append("✅ Good sepia tone effect!")
        else:
            feedback_parts.append("❌ Sepia tone conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in sepia tone verification: {e}")
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
    result = check_sepia_tone([], {}, {})
    print(f"Test result: {result}")