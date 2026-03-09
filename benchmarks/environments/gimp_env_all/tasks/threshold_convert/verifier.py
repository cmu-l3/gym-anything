#!/usr/bin/env python3
"""
Verifier for GIMP threshold conversion task.
Checks if image was converted to high-contrast black and white using threshold tool.
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


def analyze_histogram_bimodal(img):
    """
    Analyze histogram to detect bimodal distribution characteristic of threshold conversion.
    Returns metrics for bimodal quality assessment.
    """
    # Convert to grayscale for histogram analysis
    if img.mode != 'L':
        img_gray = img.convert('L')
    else:
        img_gray = img
    
    img_array = np.array(img_gray)
    
    # Calculate histogram
    hist, bins = np.histogram(img_array, bins=256, range=(0, 256))
    
    # Calculate black pixels (0-30) and white pixels (225-255)
    black_pixels = np.sum(hist[0:31])
    white_pixels = np.sum(hist[225:256])
    total_pixels = img_array.size
    
    # Calculate binary ratio (proportion of pure black/white pixels)
    binary_ratio = (black_pixels + white_pixels) / total_pixels
    
    # Detect peaks at extremes
    black_peak = np.max(hist[0:31]) if len(hist[0:31]) > 0 else 0
    white_peak = np.max(hist[225:256]) if len(hist[225:256]) > 0 else 0
    middle_max = np.max(hist[31:225]) if len(hist[31:225]) > 0 else 0
    
    # Calculate valley quality (low middle values indicate clean threshold)
    max_extreme_peak = max(black_peak, white_peak, 1)
    valley_quality = 1.0 - (middle_max / max_extreme_peak)
    
    # Combined bimodal score
    bimodal_score = (binary_ratio * 0.6 + valley_quality * 0.4)
    
    return {
        'binary_ratio': binary_ratio,
        'black_pixels': black_pixels,
        'white_pixels': white_pixels,
        'black_peak': black_peak,
        'white_peak': white_peak,
        'middle_max': middle_max,
        'valley_quality': valley_quality,
        'bimodal_score': bimodal_score
    }


def calculate_contrast_improvement(original_img, result_img):
    """Calculate contrast improvement from threshold conversion."""
    # Convert both to grayscale for comparison
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Resize if dimensions differ
    if orig_gray.size != result_gray.size:
        result_gray = result_gray.resize(orig_gray.size)
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Calculate standard deviation (measure of contrast)
    orig_std = np.std(orig_array)
    result_std = np.std(result_array)
    
    # Calculate improvement ratio
    contrast_improvement = result_std / max(orig_std, 1)
    
    return contrast_improvement


def check_meaningful_modification(original_img, result_img):
    """Check if the image was meaningfully modified."""
    # Convert to same format for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Resize if dimensions differ
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    if len(orig_array.shape) == 3:  # Color image
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale image
        diff_magnitude = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate percentage of significantly changed pixels
    significant_changes = np.sum(diff_magnitude > 30)  # Pixels changed by >30 intensity
    total_pixels = diff_magnitude.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'change_percentage': change_percentage,
        'significantly_modified': change_percentage > 10  # At least 10% changed
    }


def check_threshold_conversion(traj, env_info, task_info):
    """
    Main verifier function for threshold conversion task.
    Checks:
    1. Image shows bimodal histogram distribution (black and white peaks)
    2. High contrast improvement from original
    3. Binary dominance (most pixels are black or white)
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
        "/home/ga/Desktop/threshold_landscape.png",
        "/home/ga/Desktop/threshold_landscape.jpg", 
        "/home/ga/Desktop/threshold_landscape.jpeg",
        "/home/ga/Desktop/landscape_threshold.png",
        "/home/ga/Desktop/landscape_grayscale_threshold.png",
        "/home/ga/Desktop/landscape_grayscale_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_grayscale.jpg",
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
        
        # Analyze threshold conversion quality
        histogram_analysis = analyze_histogram_bimodal(result_image)
        contrast_improvement = calculate_contrast_improvement(original_image, result_image)
        modification_check = check_meaningful_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Binary ratio: {histogram_analysis['binary_ratio']:.2f}")
        feedback_parts.append(f"Black pixels: {histogram_analysis['black_pixels']}")
        feedback_parts.append(f"White pixels: {histogram_analysis['white_pixels']}")
        feedback_parts.append(f"Valley quality: {histogram_analysis['valley_quality']:.2f}")
        feedback_parts.append(f"Bimodal score: {histogram_analysis['bimodal_score']:.2f}")
        feedback_parts.append(f"Contrast improvement: {contrast_improvement:.2f}x")
        feedback_parts.append(f"Pixels changed: {modification_check['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Bimodal distribution (clear black and white separation)
        good_bimodal = histogram_analysis['bimodal_score'] >= 0.6
        if good_bimodal:
            criteria_met += 1
        feedback_parts.append(f"Bimodal distribution: {'✅' if good_bimodal else '❌'}")
        
        # 2. High contrast (significant improvement from original)
        high_contrast = contrast_improvement >= 1.2  # At least 20% contrast improvement
        if high_contrast:
            criteria_met += 1
        feedback_parts.append(f"High contrast: {'✅' if high_contrast else '❌'}")
        
        # 3. Binary dominance (at least 80% of pixels are black or white)
        binary_dominant = histogram_analysis['binary_ratio'] >= 0.8
        if binary_dominant:
            criteria_met += 1
        feedback_parts.append(f"Binary dominance: {'✅' if binary_dominant else '❌'}")
        
        # 4. Image modified meaningfully
        if modification_check['significantly_modified']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_check['significantly_modified'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect threshold conversion!")
        elif passed:
            feedback_parts.append("✅ Good threshold conversion!")
        else:
            feedback_parts.append("❌ Threshold conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in threshold conversion verification: {e}")
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