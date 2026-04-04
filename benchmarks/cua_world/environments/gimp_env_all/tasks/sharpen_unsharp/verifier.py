#!/usr/bin/env python3
"""
Verifier for GIMP sharpen (unsharp mask) task.
Checks if image was sharpened with appropriate enhancement without over-processing.
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

# Try to import OpenCV for advanced edge detection, use fallback if not available
try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logging.warning("OpenCV not available, using basic sharpness detection")


def calculate_sharpness_laplacian(image):
    """Calculate image sharpness using Laplacian variance method."""
    if image.mode != 'L':
        gray = image.convert('L')
    else:
        gray = image
    
    img_array = np.array(gray)
    
    if HAS_CV2:
        # Use OpenCV Laplacian for better accuracy
        laplacian = cv2.Laplacian(img_array, cv2.CV_64F)
        variance = laplacian.var()
    else:
        # Fallback: manual Laplacian kernel
        laplacian_kernel = np.array([[0, -1, 0], [-1, 4, -1], [0, -1, 0]])
        laplacian = np.abs(np.convolve(img_array.flatten(), laplacian_kernel.flatten(), mode='same')).reshape(img_array.shape)
        variance = np.var(laplacian)
    
    return variance


def calculate_edge_strength_sobel(image):
    """Calculate average edge strength using Sobel operator."""
    if image.mode != 'L':
        gray = image.convert('L')
    else:
        gray = image
    
    img_array = np.array(gray)
    
    if HAS_CV2:
        # Use OpenCV Sobel operators
        sobelx = cv2.Sobel(img_array, cv2.CV_64F, 1, 0, ksize=3)
        sobely = cv2.Sobel(img_array, cv2.CV_64F, 0, 1, ksize=3)
        edge_magnitude = np.sqrt(sobelx**2 + sobely**2)
    else:
        # Fallback: manual Sobel kernels
        sobel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
        sobel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]])
        
        # Apply convolution (simplified)
        height, width = img_array.shape
        edge_x = np.zeros_like(img_array, dtype=np.float64)
        edge_y = np.zeros_like(img_array, dtype=np.float64)
        
        for i in range(1, height-1):
            for j in range(1, width-1):
                edge_x[i, j] = np.sum(sobel_x * img_array[i-1:i+2, j-1:j+2])
                edge_y[i, j] = np.sum(sobel_y * img_array[i-1:i+2, j-1:j+2])
        
        edge_magnitude = np.sqrt(edge_x**2 + edge_y**2)
    
    return np.mean(edge_magnitude)


def detect_over_sharpening(original_img, result_img):
    """Detect signs of over-sharpening (excessive artifacts, halos, noise amplification)."""
    # Convert to grayscale for analysis
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
    
    # Check for excessive contrast increase (sign of over-sharpening)
    orig_std = np.std(orig_array)
    result_std = np.std(result_array)
    contrast_increase = (result_std - orig_std) / orig_std if orig_std > 0 else 0
    
    # Check for noise amplification in flat areas
    # Find relatively flat areas (low gradient)
    if HAS_CV2:
        gradients = cv2.Sobel(orig_array, cv2.CV_64F, 1, 1, ksize=3)
        flat_mask = np.abs(gradients) < np.percentile(np.abs(gradients), 25)  # Bottom 25% of gradients
    else:
        # Simplified flat area detection
        flat_mask = np.abs(orig_array - np.mean(orig_array)) < np.std(orig_array) * 0.5
    
    if np.sum(flat_mask) > 0:
        orig_flat_noise = np.std(orig_array[flat_mask])
        result_flat_noise = np.std(result_array[flat_mask])
        noise_amplification = (result_flat_noise - orig_flat_noise) / orig_flat_noise if orig_flat_noise > 0 else 0
    else:
        noise_amplification = 0
    
    # Over-sharpening indicators
    over_sharpened = (
        contrast_increase > 0.8 or  # More than 80% contrast increase
        noise_amplification > 0.5   # More than 50% noise increase in flat areas
    )
    
    return {
        'over_sharpened': over_sharpened,
        'contrast_increase': contrast_increase,
        'noise_amplification': noise_amplification
    }


def check_meaningful_modification(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Resize result to match original if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    if len(orig_array.shape) == 3:  # RGB
        diff = np.sqrt(np.sum((orig_array.astype(np.float32) - result_array.astype(np.float32))**2, axis=2))
    else:  # Grayscale
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    mean_diff = np.mean(diff)
    significant_pixels = np.sum(diff > 10)  # Pixels with >10 intensity change
    total_pixels = diff.size
    change_percentage = (significant_pixels / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 2  # At least 2% of pixels changed
    }


def check_sharpen_unsharp(traj, env_info, task_info):
    """
    Main verifier function for sharpen (unsharp mask) task.
    Checks:
    1. Image sharpness was increased (10-50% improvement range)
    2. No excessive over-sharpening artifacts
    3. Image was meaningfully modified
    4. Enhancement is within professional acceptable range
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
        "/home/ga/Desktop/sharpened_image.jpg",
        "/home/ga/Desktop/sharpened_image.png", 
        "/home/ga/Desktop/sharpened_image.jpeg",
        "/home/ga/Desktop/portrait_sharpen_edited.jpg",
        "/home/ga/Desktop/portrait_sharpened.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_sharpen.jpg",
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
        
        # Calculate sharpness metrics
        orig_laplacian = calculate_sharpness_laplacian(original_image)
        result_laplacian = calculate_sharpness_laplacian(result_image)
        
        orig_sobel = calculate_edge_strength_sobel(original_image)
        result_sobel = calculate_edge_strength_sobel(result_image)
        
        # Calculate improvements
        laplacian_increase = (result_laplacian - orig_laplacian) / orig_laplacian if orig_laplacian > 0 else 0
        sobel_increase = (result_sobel - orig_sobel) / orig_sobel if orig_sobel > 0 else 0
        
        # Check for over-sharpening
        over_sharp_analysis = detect_over_sharpening(original_image, result_image)
        
        # Check for meaningful modification
        modification_analysis = check_meaningful_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Laplacian sharpness increase: {laplacian_increase:.1%}")
        feedback_parts.append(f"Sobel edge strength increase: {sobel_increase:.1%}")
        feedback_parts.append(f"Pixels changed: {modification_analysis['change_percentage']:.1f}%")
        feedback_parts.append(f"Over-sharpened: {'❌' if over_sharp_analysis['over_sharpened'] else '✅'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Sharpness increased appropriately (10-50% improvement)
        sharpness_improved = (laplacian_increase >= 0.10 or sobel_increase >= 0.10) and \
                           (laplacian_increase <= 0.80 and sobel_increase <= 0.80)  # Not over-sharpened
        if sharpness_improved:
            criteria_met += 1
        feedback_parts.append(f"Sharpness improved (10-80%): {'✅' if sharpness_improved else '❌'}")
        
        # 2. No over-sharpening artifacts
        quality_maintained = not over_sharp_analysis['over_sharpened']
        if quality_maintained:
            criteria_met += 1
        feedback_parts.append(f"Quality maintained: {'✅' if quality_maintained else '❌'}")
        
        # 3. Image was meaningfully modified
        if modification_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_analysis['meaningfully_changed'] else '❌'}")
        
        # 4. Enhancement in appropriate range (significant but not excessive)
        appropriate_range = (laplacian_increase >= 0.05 or sobel_increase >= 0.05) and \
                          (laplacian_increase < 0.60 and sobel_increase < 0.60)
        if appropriate_range:
            criteria_met += 1
        feedback_parts.append(f"Appropriate enhancement range: {'✅' if appropriate_range else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent image sharpening!")
        elif passed:
            feedback_parts.append("✅ Good image sharpening!")
        else:
            feedback_parts.append("❌ Image sharpening needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in sharpen verification: {e}")
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
    result = check_sharpen_unsharp([], {}, {})
    print(f"Test result: {result}")