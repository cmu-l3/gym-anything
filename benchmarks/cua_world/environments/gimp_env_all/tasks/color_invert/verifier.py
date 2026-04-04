#!/usr/bin/env python3
"""
Verifier for GIMP color inversion task.
Checks if colors were successfully inverted using mathematical pixel comparison.
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

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
        HAS_SSIM = True
    except ImportError:
        HAS_SSIM = False
        logging.warning("SSIM not available, using basic pixel comparison")


def generate_perfect_inversion(img):
    """
    Generate mathematically perfect color inversion where each RGB value
    becomes (255 - original_value).
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    # Convert to numpy array
    img_array = np.array(img)
    
    # Mathematical inversion: new_value = 255 - old_value for each RGB channel
    inverted_array = 255 - img_array
    
    # Convert back to PIL Image
    inverted_image = Image.fromarray(inverted_array.astype(np.uint8))
    
    return inverted_image


def compare_with_perfect_inversion(original_img, result_img, threshold=0.95):
    """
    Compare result image with mathematically perfect inversion using SSIM.
    """
    if not HAS_SSIM:
        # Fallback to pixel-wise comparison if SSIM not available
        return compare_pixel_inversion(original_img, result_img)
    
    # Generate perfect reference inversion
    perfect_inversion = generate_perfect_inversion(original_img)
    
    # Ensure images are same size
    if perfect_inversion.size != result_img.size:
        result_img = result_img.resize(perfect_inversion.size)
    
    # Convert to RGB if needed
    if perfect_inversion.mode != 'RGB':
        perfect_inversion = perfect_inversion.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    perfect_array = np.array(perfect_inversion)
    result_array = np.array(result_img)
    
    # Calculate SSIM
    try:
        # Try newer SSIM API first
        try:
            similarity = ssim(perfect_array, result_array, win_size=7, channel_axis=2)
        except TypeError:
            # Fallback to older API
            similarity = ssim(perfect_array, result_array, win_size=7, multichannel=True)
        
        logging.debug(f"SSIM similarity with perfect inversion: {similarity:.4f}")
        return similarity >= threshold
        
    except Exception as e:
        logging.error(f"SSIM calculation failed: {e}")
        return compare_pixel_inversion(original_img, result_img)


def compare_pixel_inversion(original_img, result_img):
    """
    Fallback pixel-wise comparison for color inversion verification.
    """
    # Generate perfect reference inversion
    perfect_inversion = generate_perfect_inversion(original_img)
    
    # Ensure same size
    if perfect_inversion.size != result_img.size:
        result_img = result_img.resize(perfect_inversion.size)
    
    # Convert to RGB
    if perfect_inversion.mode != 'RGB':
        perfect_inversion = perfect_inversion.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to arrays and calculate difference
    perfect_array = np.array(perfect_inversion).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    # Calculate mean absolute difference
    diff = np.abs(perfect_array - result_array)
    mean_diff = np.mean(diff)
    
    # Good inversion should have very low difference (< 10 intensity units on average)
    logging.debug(f"Mean pixel difference from perfect inversion: {mean_diff:.2f}")
    return mean_diff < 10.0


def detect_significant_color_changes(original_img, result_img):
    """
    Detect if significant color changes occurred throughout the image.
    """
    # Ensure same size and format
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to arrays
    orig_array = np.array(original_img).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array - result_array)
    
    # Calculate statistics
    mean_diff = np.mean(diff)
    pixels_changed_significantly = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 50)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (pixels_changed_significantly / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'pixels_changed_significantly': pixels_changed_significantly,
        'total_pixels': total_pixels,
        'change_percentage': change_percentage,
        'significant_change': change_percentage > 70  # At least 70% of pixels changed significantly
    }


def analyze_histogram_inversion(original_img, result_img):
    """
    Analyze if the color histograms show proper inversion relationship.
    For true inversion, the histogram should be flipped.
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Get histograms for each channel
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    correlations = []
    
    for channel in range(3):  # R, G, B channels
        # Get histograms
        orig_hist, _ = np.histogram(orig_array[:, :, channel], bins=256, range=[0, 256])
        result_hist, _ = np.histogram(result_array[:, :, channel], bins=256, range=[0, 256])
        
        # For perfect inversion, result histogram should be flipped version of original
        flipped_orig_hist = np.flip(orig_hist)
        
        # Calculate correlation
        if np.sum(flipped_orig_hist) > 0 and np.sum(result_hist) > 0:
            correlation = np.corrcoef(flipped_orig_hist, result_hist)[0, 1]
            if not np.isnan(correlation):
                correlations.append(correlation)
    
    if len(correlations) > 0:
        avg_correlation = np.mean(correlations)
        return avg_correlation > 0.7  # Good correlation indicates proper inversion
    
    return False


def check_color_inversion(traj, env_info, task_info):
    """
    Main verifier function for color inversion task.
    Checks:
    1. Image colors were mathematically inverted (SSIM comparison with perfect inversion)
    2. Significant color changes occurred throughout the image
    3. Histogram analysis confirms inversion relationship
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
        "/home/ga/Desktop/inverted_image.jpg",
        "/home/ga/Desktop/inverted_image.png", 
        "/home/ga/Desktop/inverted_image.jpeg",
        "/home/ga/Desktop/original_photo_inverted.jpg",
        "/home/ga/Desktop/photo_inverted.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/original_photo.jpg",
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
        
        # Check if result matches perfect mathematical inversion
        perfect_inversion_match = compare_with_perfect_inversion(original_image, result_image)
        
        # Detect significant color changes
        change_analysis = detect_significant_color_changes(original_image, result_image)
        
        # Analyze histogram inversion
        histogram_inverted = analyze_histogram_inversion(original_image, result_image)
        
        # Check if images are different
        images_different = original_image.size != result_image.size or not np.array_equal(
            np.array(original_image.convert('RGB')), 
            np.array(result_image.convert('RGB'))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Mean color difference: {change_analysis['mean_difference']:.1f}")
        feedback_parts.append(f"Pixels changed significantly: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Perfect mathematical inversion match
        if perfect_inversion_match:
            criteria_met += 1
        feedback_parts.append(f"Perfect inversion match: {'✅' if perfect_inversion_match else '❌'}")
        
        # 2. Significant color changes detected
        if change_analysis['significant_change']:
            criteria_met += 1
        feedback_parts.append(f"Significant color changes: {'✅' if change_analysis['significant_change'] else '❌'}")
        
        # 3. Histogram analysis confirms inversion
        if histogram_inverted:
            criteria_met += 1
        feedback_parts.append(f"Histogram inversion confirmed: {'✅' if histogram_inverted else '❌'}")
        
        # 4. Image was modified from original
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect color inversion!")
        elif passed:
            feedback_parts.append("✅ Good color inversion!")
        else:
            feedback_parts.append("❌ Color inversion not successful")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color inversion verification: {e}")
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
    result = check_color_inversion([], {}, {})
    print(f"Test result: {result}")