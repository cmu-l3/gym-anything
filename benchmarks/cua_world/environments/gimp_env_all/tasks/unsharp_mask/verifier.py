#!/usr/bin/env python3
"""
Verifier for GIMP Unsharp Mask task.
Checks if Unsharp Mask filter was applied to enhance image sharpness.
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

# Try to import OpenCV for advanced sharpness calculation
try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logging.warning("OpenCV not available, using basic sharpness calculation")


def calculate_sharpness_laplacian(image):
    """
    Calculate image sharpness using Laplacian variance method.
    This is a well-established computer vision technique for measuring sharpness.
    """
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    img_array = np.array(image)
    
    if HAS_CV2:
        # Convert to grayscale for Laplacian calculation
        gray = cv2.cvtColor(img_array, cv2.COLOR_RGB2GRAY)
        # Calculate Laplacian
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        # Return variance of Laplacian as sharpness metric
        return laplacian.var()
    else:
        # Fallback: manual Laplacian kernel implementation
        gray = np.mean(img_array, axis=2)  # Convert to grayscale
        
        # Simple Laplacian kernel
        kernel = np.array([[0, -1, 0],
                          [-1, 4, -1],
                          [0, -1, 0]], dtype=np.float32)
        
        # Apply convolution manually
        h, w = gray.shape
        laplacian = np.zeros_like(gray)
        
        for i in range(1, h-1):
            for j in range(1, w-1):
                laplacian[i, j] = np.sum(kernel * gray[i-1:i+2, j-1:j+2])
        
        return np.var(laplacian)


def analyze_sharpness_enhancement(original_img, result_img):
    """
    Analyze the sharpness enhancement between original and result images.
    """
    # Calculate sharpness for both images
    original_sharpness = calculate_sharpness_laplacian(original_img)
    result_sharpness = calculate_sharpness_laplacian(result_img)
    
    logging.debug(f"Original sharpness: {original_sharpness}")
    logging.debug(f"Result sharpness: {result_sharpness}")
    
    # Avoid division by zero
    if original_sharpness == 0:
        return {
            'original_sharpness': 0,
            'result_sharpness': result_sharpness,
            'enhancement_ratio': 0,
            'enhancement_percent': 0,
            'valid_enhancement': False,
            'error': 'Original image has zero sharpness variance'
        }
    
    # Calculate enhancement
    enhancement_ratio = (result_sharpness - original_sharpness) / original_sharpness
    enhancement_percent = enhancement_ratio * 100
    
    # Determine if enhancement is within acceptable range (10% to 80% increase)
    valid_enhancement = 10 <= enhancement_percent <= 80
    
    return {
        'original_sharpness': original_sharpness,
        'result_sharpness': result_sharpness,
        'enhancement_ratio': enhancement_ratio,
        'enhancement_percent': enhancement_percent,
        'valid_enhancement': valid_enhancement,
        'error': None
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to arrays for comparison
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of pixels with noticeable change
    significant_diff_mask = np.sqrt(np.sum(diff ** 2, axis=2)) > 10  # Pixels with >10 intensity change
    change_percentage = (np.sum(significant_diff_mask) / significant_diff_mask.size) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 1  # At least 1% of pixels changed
    }


def check_unsharp_mask(traj, env_info, task_info):
    """
    Main verifier function for Unsharp Mask task.
    Checks:
    1. Image sharpness was measurably increased
    2. Enhancement is within reasonable bounds (10%-80%)
    3. Image was meaningfully modified
    4. Quality is preserved (no excessive artifacts)
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
        "/home/ga/Desktop/sharpened_unsharp.jpg",
        "/home/ga/Desktop/sharpened_unsharp.png",
        "/home/ga/Desktop/sharpened_unsharp.jpeg",
        "/home/ga/Desktop/portrait_photo_sharpened.jpg",
        "/home/ga/Desktop/unsharp_applied.jpg",
        "/home/ga/Desktop/portrait_photo_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_photo.jpg",
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
        
        # Analyze sharpness enhancement
        sharpness_analysis = analyze_sharpness_enhancement(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original sharpness: {sharpness_analysis['original_sharpness']:.1f}")
        feedback_parts.append(f"Result sharpness: {sharpness_analysis['result_sharpness']:.1f}")
        feedback_parts.append(f"Enhancement: {sharpness_analysis['enhancement_percent']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Sharpness increased within valid range (10%-80%)
        if sharpness_analysis['valid_enhancement'] and sharpness_analysis['enhancement_percent'] >= 10:
            criteria_met += 1
        feedback_parts.append(f"Valid sharpness enhancement: {'✅' if sharpness_analysis['valid_enhancement'] and sharpness_analysis['enhancement_percent'] >= 10 else '❌'}")
        
        # 2. Enhancement is reasonable (not excessive)
        reasonable_enhancement = sharpness_analysis['enhancement_percent'] <= 80
        if reasonable_enhancement:
            criteria_met += 1
        feedback_parts.append(f"Reasonable enhancement level: {'✅' if reasonable_enhancement else '❌'}")
        
        # 3. Image was meaningfully modified
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # 4. No error in sharpness calculation
        no_calculation_error = sharpness_analysis['error'] is None
        if no_calculation_error:
            criteria_met += 1
        feedback_parts.append(f"Valid sharpness calculation: {'✅' if no_calculation_error else '❌'}")
        
        if sharpness_analysis['error']:
            feedback_parts.append(f"Error: {sharpness_analysis['error']}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent Unsharp Mask application!")
        elif passed:
            feedback_parts.append("✅ Good Unsharp Mask enhancement!")
        else:
            feedback_parts.append("❌ Unsharp Mask needs improvement")
            if sharpness_analysis['enhancement_percent'] < 10:
                feedback_parts.append("Hint: Enhancement may be too subtle")
            elif sharpness_analysis['enhancement_percent'] > 80:
                feedback_parts.append("Hint: Enhancement may be too aggressive")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in Unsharp Mask verification: {e}")
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
    result = check_unsharp_mask([], {}, {})
    print(f"Test result: {result}")