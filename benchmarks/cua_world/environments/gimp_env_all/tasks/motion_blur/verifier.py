#!/usr/bin/env python3
"""
Verifier for GIMP motion blur task.
Checks if horizontal motion blur was successfully applied to the image.
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


def analyze_directional_blur(original_img, result_img):
    """
    Analyze directional blur by computing gradients and measuring blur anisotropy.
    Returns metrics indicating horizontal vs vertical blur strength.
    """
    # Convert to grayscale for gradient analysis
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Ensure same size
    if original_gray.size != result_gray.size:
        result_gray = result_gray.resize(original_gray.size)
    
    orig_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    try:
        # Try to use scipy for more accurate gradient computation
        from scipy.ndimage import sobel
        
        # Calculate gradients in both directions for original
        orig_grad_h = sobel(orig_array, axis=1)  # Horizontal gradients (vertical edges)
        orig_grad_v = sobel(orig_array, axis=0)  # Vertical gradients (horizontal edges)
        
        # Calculate gradients for result
        result_grad_h = sobel(result_array, axis=1)
        result_grad_v = sobel(result_array, axis=0)
        
        # Calculate gradient strengths (standard deviation of gradients)
        orig_h_strength = np.std(orig_grad_h)
        orig_v_strength = np.std(orig_grad_v)
        result_h_strength = np.std(result_grad_h)
        result_v_strength = np.std(result_grad_v)
        
    except ImportError:
        # Fallback: use simple numpy gradient
        logging.warning("scipy not available, using numpy gradient fallback")
        
        # Calculate gradients using numpy
        orig_grad_h = np.gradient(orig_array, axis=1)
        orig_grad_v = np.gradient(orig_array, axis=0)
        result_grad_h = np.gradient(result_array, axis=1)
        result_grad_v = np.gradient(result_array, axis=0)
        
        # Calculate gradient strengths
        orig_h_strength = np.std(orig_grad_h)
        orig_v_strength = np.std(orig_grad_v)
        result_h_strength = np.std(result_grad_h)
        result_v_strength = np.std(result_grad_v)
    
    # Calculate blur strength (reduction in gradient strength)
    h_blur_strength = max(0, (orig_h_strength - result_h_strength) / max(orig_h_strength, 1e-6))
    v_blur_strength = max(0, (orig_v_strength - result_v_strength) / max(orig_v_strength, 1e-6))
    
    # Calculate directionality ratio (horizontal blur should be stronger for motion blur)
    directionality_ratio = h_blur_strength / max(v_blur_strength, 1e-6)
    
    return {
        'horizontal_blur_strength': h_blur_strength,
        'vertical_blur_strength': v_blur_strength,
        'directionality_ratio': directionality_ratio,
        'is_horizontal_blur': directionality_ratio > 1.5,  # Horizontal blur should be at least 1.5x stronger
        'orig_h_strength': orig_h_strength,
        'orig_v_strength': orig_v_strength,
        'result_h_strength': result_h_strength,
        'result_v_strength': result_v_strength
    }


def assess_blur_magnitude(original_img, result_img):
    """
    Measure overall blur magnitude using pixel variance reduction.
    """
    # Convert to grayscale arrays
    orig_array = np.array(original_img.convert('L'))
    result_array = np.array(result_img.convert('L'))
    
    # Ensure same size
    if orig_array.shape != result_array.shape:
        from PIL import Image
        result_img_resized = Image.fromarray(result_array).resize((orig_array.shape[1], orig_array.shape[0]))
        result_array = np.array(result_img_resized)
    
    # Calculate variance reduction (blur reduces image variance)
    orig_variance = np.var(orig_array)
    result_variance = np.var(result_array)
    variance_reduction = (orig_variance - result_variance) / max(orig_variance, 1e-6)
    
    # Calculate mean pixel-wise difference
    pixel_diff = np.mean(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)))
    
    return {
        'variance_reduction': variance_reduction,
        'pixel_difference': pixel_diff,
        'is_appropriate_blur': 0.15 <= variance_reduction <= 0.65,  # 15-65% variance reduction
        'orig_variance': orig_variance,
        'result_variance': result_variance
    }


def check_image_modification(original_img, result_img):
    """Check if the image was significantly modified."""
    # Convert to same mode and size
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    if len(orig_array.shape) == 3:  # Color image
        diff = np.sqrt(np.sum((orig_array.astype(np.float32) - result_array.astype(np.float32)) ** 2, axis=2))
    else:  # Grayscale
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate change statistics
    mean_change = np.mean(diff)
    significant_changes = np.sum(diff > 20)  # Pixels with >20 intensity change
    total_pixels = diff.shape[0] * diff.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_change': mean_change,
        'change_percentage': change_percentage,
        'is_meaningfully_changed': change_percentage > 10  # At least 10% of pixels significantly changed
    }


def check_motion_blur(traj, env_info, task_info):
    """
    Main verifier function for motion blur task.
    Checks:
    1. Horizontal motion blur was applied (directional blur analysis)
    2. Blur magnitude is appropriate (not too weak, not excessive)
    3. Image was meaningfully modified
    4. Quality is preserved (recognizable subject)
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
        "/home/ga/Desktop/motion_blur_result.jpg",
        "/home/ga/Desktop/motion_blur_result.png", 
        "/home/ga/Desktop/motion_blur_result.jpeg",
        "/home/ga/Desktop/sports_action_blur.jpg",
        "/home/ga/Desktop/blurred_sports.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/sports_action.jpg",
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
        
        # Analyze directional blur
        blur_analysis = analyze_directional_blur(original_image, result_image)
        
        # Assess blur magnitude
        magnitude_analysis = assess_blur_magnitude(original_image, result_image)
        
        # Check image modification
        modification_analysis = check_image_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Horizontal blur strength: {blur_analysis['horizontal_blur_strength']:.3f}")
        feedback_parts.append(f"Vertical blur strength: {blur_analysis['vertical_blur_strength']:.3f}")
        feedback_parts.append(f"Directionality ratio: {blur_analysis['directionality_ratio']:.2f}")
        feedback_parts.append(f"Variance reduction: {magnitude_analysis['variance_reduction']:.3f}")
        feedback_parts.append(f"Pixels changed: {modification_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Horizontal motion blur detected (directionality)
        if blur_analysis['is_horizontal_blur']:
            criteria_met += 1
        feedback_parts.append(f"Horizontal motion blur: {'✅' if blur_analysis['is_horizontal_blur'] else '❌'}")
        
        # 2. Appropriate blur magnitude
        if magnitude_analysis['is_appropriate_blur']:
            criteria_met += 1
        feedback_parts.append(f"Appropriate blur strength: {'✅' if magnitude_analysis['is_appropriate_blur'] else '❌'}")
        
        # 3. Image meaningfully modified
        if modification_analysis['is_meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_analysis['is_meaningfully_changed'] else '❌'}")
        
        # 4. Significant horizontal blur (strength > 0.1)
        significant_blur = blur_analysis['horizontal_blur_strength'] > 0.1
        if significant_blur:
            criteria_met += 1
        feedback_parts.append(f"Significant blur applied: {'✅' if significant_blur else '❌'}")
        
        # 5. Quality maintained (variance reduction not excessive)
        quality_maintained = magnitude_analysis['variance_reduction'] < 0.8  # Not more than 80% variance lost
        if quality_maintained:
            criteria_met += 1
        feedback_parts.append(f"Quality preserved: {'✅' if quality_maintained else '❌'}")
        
        # Calculate score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect motion blur applied!")
        elif passed:
            feedback_parts.append("✅ Good motion blur effect!")
        else:
            feedback_parts.append("❌ Motion blur needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in motion blur verification: {e}")
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
    result = check_motion_blur([], {}, {})
    print(f"Test result: {result}")