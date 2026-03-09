#!/usr/bin/env python3
"""
Verifier for GIMP threshold black and white task.
Checks if image was converted to pure black and white (binary) with no grayscale.
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


def analyze_binary_purity(img):
    """
    Comprehensively analyze how close the image is to pure binary black and white.
    
    Returns dict with detailed analysis metrics.
    """
    if img.mode != 'L':
        img_gray = img.convert('L')
    else:
        img_gray = img
    
    img_array = np.array(img_gray)
    total_pixels = img_array.size
    
    # Count pixels in different brightness ranges
    near_black = np.sum(img_array <= 25)      # Very dark pixels (pure black)
    near_white = np.sum(img_array >= 230)     # Very light pixels (pure white)
    gray_pixels = np.sum((img_array > 25) & (img_array < 230))  # Gray pixels
    
    binary_percentage = (near_black + near_white) / total_pixels * 100
    
    # Analyze histogram for bimodal distribution
    hist, bins = np.histogram(img_array, bins=256, range=(0, 256))
    
    # Check for peaks at extremes and absence of mid-tones
    black_peak = np.sum(hist[0:35])           # Pixels in black range
    white_peak = np.sum(hist[221:256])        # Pixels in white range
    middle_gray = np.sum(hist[80:176])        # Mid-tone pixels (should be minimal)
    
    # Calculate balance (avoid 99% black or 99% white images)
    black_ratio = near_black / total_pixels
    white_ratio = near_white / total_pixels
    is_balanced = (black_ratio < 0.90) and (white_ratio < 0.90)
    
    return {
        'binary_percentage': binary_percentage,
        'near_black_count': near_black,
        'near_white_count': near_white,
        'gray_count': gray_pixels,
        'black_peak': black_peak,
        'white_peak': white_peak,
        'middle_gray_count': middle_gray,
        'is_bimodal': (middle_gray / total_pixels) < 0.05,  # <5% mid-tones
        'is_balanced': is_balanced,
        'standard_deviation': np.std(img_array),  # Should be high for binary
        'black_ratio': black_ratio,
        'white_ratio': white_ratio
    }


def check_color_removal(original_img, result_img):
    """
    Check if all color information was removed (R=G=B for all pixels).
    """
    if result_img.mode != 'RGB':
        result_rgb = result_img.convert('RGB')
    else:
        result_rgb = result_img
    
    result_array = np.array(result_rgb)
    
    # Check if R=G=B for all pixels (true grayscale/monochrome)
    r_channel = result_array[:, :, 0]
    g_channel = result_array[:, :, 1] 
    b_channel = result_array[:, :, 2]
    
    # Allow small tolerance for compression artifacts
    tolerance = 2
    rg_equal = np.abs(r_channel.astype(np.int16) - g_channel.astype(np.int16)) <= tolerance
    rb_equal = np.abs(r_channel.astype(np.int16) - b_channel.astype(np.int16)) <= tolerance
    gb_equal = np.abs(g_channel.astype(np.int16) - b_channel.astype(np.int16)) <= tolerance
    
    all_equal = rg_equal & rb_equal & gb_equal
    color_removed_percentage = (np.sum(all_equal) / all_equal.size) * 100
    
    return {
        'color_removed_percentage': color_removed_percentage,
        'is_monochrome': color_removed_percentage >= 95  # At least 95% achromatic
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Convert both to grayscale for fair comparison
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Ensure same size
    if orig_gray.size != result_gray.size:
        result_gray = result_gray.resize(orig_gray.size)
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(diff > 30)  # Pixels with >30 intensity change
    total_pixels = orig_array.size
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed significantly
    }


def check_threshold_conversion(traj, env_info, task_info):
    """
    Main verifier function for threshold conversion task.
    Checks:
    1. High binary purity (≥95% pure black/white pixels)
    2. Bimodal distribution (peaks at extremes)
    3. Balanced result (neither color dominates >90%)
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
        "/home/ga/Desktop/threshold_bw.png",
        "/home/ga/Desktop/threshold_bw.jpg", 
        "/home/ga/Desktop/threshold_bw.jpeg",
        "/home/ga/Desktop/color_photo_bw.png",
        "/home/ga/Desktop/color_photo_threshold.png"
    ]
    breakpoint()
    
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
        
        # Analyze binary purity
        binary_analysis = analyze_binary_purity(result_image)
        
        # Check color removal
        color_analysis = check_color_removal(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Binary purity: {binary_analysis['binary_percentage']:.1f}%")
        feedback_parts.append(f"Near black pixels: {binary_analysis['near_black_count']}")
        feedback_parts.append(f"Near white pixels: {binary_analysis['near_white_count']}")
        feedback_parts.append(f"Gray pixels: {binary_analysis['gray_count']}")
        feedback_parts.append(f"Standard deviation: {binary_analysis['standard_deviation']:.1f}")
        feedback_parts.append(f"Color removed: {color_analysis['color_removed_percentage']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. High binary purity (≥95% pure black/white pixels)
        high_binary_purity = binary_analysis['binary_percentage'] >= 95.0
        if high_binary_purity:
            criteria_met += 1
        feedback_parts.append(f"High binary purity (≥95%): {'✅' if high_binary_purity else '❌'}")
        
        # 2. Bimodal distribution (clear peaks at extremes, minimal mid-tones)
        bimodal_distribution = binary_analysis['is_bimodal']
        if bimodal_distribution:
            criteria_met += 1
        feedback_parts.append(f"Bimodal distribution: {'✅' if bimodal_distribution else '❌'}")
        
        # 3. Balanced result (neither black nor white dominates >90%)
        balanced_result = binary_analysis['is_balanced']
        if balanced_result:
            criteria_met += 1
        feedback_parts.append(f"Balanced result: {'✅' if balanced_result else '❌'}")
        
        # 4. Meaningful change from original
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image substantially modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 98:
            feedback_parts.append("🎉 Perfect binary threshold conversion!")
        elif passed:
            feedback_parts.append("✅ Good threshold conversion to black and white!")
        else:
            feedback_parts.append("❌ Threshold conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in threshold verification: {e}")
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
    result = check_threshold_conversion([], {}, {})
    print(f"Test result: {result}")