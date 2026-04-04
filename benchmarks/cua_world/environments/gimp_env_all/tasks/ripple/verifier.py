#!/usr/bin/env python3
"""
Verifier for GIMP ripple effect task.
Checks if ripple distortion effect was successfully applied to the image.
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


def detect_ripple_distortion(original_img, result_img):
    """
    Detect if ripple distortion has been applied by analyzing geometric changes.
    Uses SSIM and edge analysis to identify wave-like distortions.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    orig_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    # Calculate structural similarity (should be reduced by ripple distortion)
    try:
        from skimage.metrics import structural_similarity as ssim
        ssim_score = ssim(orig_array, result_array, win_size=7)
    except ImportError:
        # Fallback similarity calculation if scikit-image not available
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        ssim_score = 1.0 - (np.mean(diff) / 255.0)
    
    # Calculate pixel displacement magnitude
    pixel_diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    displacement_magnitude = np.mean(pixel_diff)
    
    # Check for distributed changes (not localized)
    significant_change_mask = pixel_diff > 20  # Pixels changed by more than 20 intensity units
    changed_percentage = np.sum(significant_change_mask) / significant_change_mask.size
    
    # Basic wave pattern detection through edge analysis
    try:
        from scipy import ndimage
        # Calculate edges in both images
        orig_edges = ndimage.sobel(orig_array)
        result_edges = ndimage.sobel(result_array)
        edge_change = np.std(result_edges - orig_edges)
        wave_pattern_detected = edge_change > 5.0
    except ImportError:
        # Fallback edge detection using basic gradient
        orig_grad_x = np.abs(np.diff(orig_array, axis=1))
        orig_grad_y = np.abs(np.diff(orig_array, axis=0))
        result_grad_x = np.abs(np.diff(result_array, axis=1))
        result_grad_y = np.abs(np.diff(result_array, axis=0))
        
        # Pad arrays to same size
        min_x_size = min(orig_grad_x.shape[1], result_grad_x.shape[1])
        min_y_size = min(orig_grad_y.shape[0], result_grad_y.shape[0])
        
        edge_change_x = np.std(result_grad_x[:, :min_x_size] - orig_grad_x[:, :min_x_size])
        edge_change_y = np.std(result_grad_y[:min_y_size, :] - orig_grad_y[:min_y_size, :])
        edge_change = (edge_change_x + edge_change_y) / 2.0
        wave_pattern_detected = edge_change > 3.0
    
    return {
        'ssim_score': ssim_score,
        'significant_distortion': (ssim_score < 0.85),
        'distributed_effect': (changed_percentage > 0.20),
        'wave_pattern_detected': wave_pattern_detected,
        'content_preserved': (ssim_score > 0.40),
        'displacement_magnitude': displacement_magnitude,
        'changed_percentage': changed_percentage * 100,
        'edge_change': edge_change
    }


def check_ripple_effect(traj, env_info, task_info):
    """
    Main verifier function for ripple effect task.
    Checks:
    1. Significant geometric distortion applied (SSIM < 0.85)
    2. Distortion distributed across image (>20% of pixels affected)
    3. Wave-like pattern detected in edge analysis
    4. Image content preserved (not completely destroyed, SSIM > 0.40)
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
        "/home/ga/Desktop/ripple_effect.jpg",
        "/home/ga/Desktop/ripple_effect.png",
        "/home/ga/Desktop/ripple_effect.jpeg",
        "/home/ga/Desktop/photo_ripple.jpg",
        "/home/ga/Desktop/photo_image_ripple.jpg",
        "/home/ga/Desktop/distorted_photo.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_image.jpg",
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
        
        # Analyze ripple distortion
        distortion_analysis = detect_ripple_distortion(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"SSIM score: {distortion_analysis['ssim_score']:.3f}")
        feedback_parts.append(f"Pixels changed: {distortion_analysis['changed_percentage']:.1f}%")
        feedback_parts.append(f"Edge change: {distortion_analysis['edge_change']:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant distortion (SSIM < 0.85)
        if distortion_analysis['significant_distortion']:
            criteria_met += 1
        feedback_parts.append(f"Significant distortion: {'✅' if distortion_analysis['significant_distortion'] else '❌'}")
        
        # 2. Distributed effect (>20% of pixels affected)
        if distortion_analysis['distributed_effect']:
            criteria_met += 1
        feedback_parts.append(f"Distributed effect: {'✅' if distortion_analysis['distributed_effect'] else '❌'}")
        
        # 3. Wave pattern detected
        if distortion_analysis['wave_pattern_detected']:
            criteria_met += 1
        feedback_parts.append(f"Wave pattern detected: {'✅' if distortion_analysis['wave_pattern_detected'] else '❌'}")
        
        # 4. Content preserved (not completely destroyed)
        if distortion_analysis['content_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Content preserved: {'✅' if distortion_analysis['content_preserved'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent ripple effect applied!")
        elif passed:
            feedback_parts.append("✅ Good ripple effect applied!")
        else:
            feedback_parts.append("❌ Ripple effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in ripple effect verification: {e}")
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
    result = check_ripple_effect([], {}, {})
    print(f"Test result: {result}")