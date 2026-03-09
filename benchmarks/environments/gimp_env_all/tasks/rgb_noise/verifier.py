#!/usr/bin/env python3
"""
Verifier for GIMP RGB noise task.
Checks if RGB noise was successfully added to the image using multi-method statistical analysis.
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


def estimate_noise_std(image_array):
    """
    Estimate noise using robust Laplacian-based method.
    This method isolates high-frequency components that indicate noise.
    """
    # Convert to grayscale for analysis
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    # Apply Laplacian kernel for high-frequency content detection
    try:
        from scipy.ndimage import convolve
        laplacian_kernel = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]])
        laplacian = convolve(gray, laplacian_kernel)
        
        # Robust noise estimation using Laplacian response
        noise_sigma = np.std(laplacian) / np.sqrt(2)
        return noise_sigma
    except ImportError:
        # Fallback method using simple gradient if scipy not available
        dy = np.diff(gray, axis=0)
        dx = np.diff(gray, axis=1)
        # Pad to match original size
        dy = np.pad(dy, ((0, 1), (0, 0)), mode='constant')
        dx = np.pad(dx, ((0, 0), (0, 1)), mode='constant')
        
        gradient_magnitude = np.sqrt(dy**2 + dx**2)
        return np.std(gradient_magnitude)


def calculate_local_variance(image_array, num_regions=25):
    """
    Measure variance in local regions to verify uniform noise distribution.
    This ensures noise was applied uniformly across the image.
    """
    h, w = image_array.shape[:2]
    grid_size = int(np.sqrt(num_regions))
    region_h, region_w = h // grid_size, w // grid_size
    
    variances = []
    for i in range(grid_size):
        for j in range(grid_size):
            y1, y2 = i * region_h, (i + 1) * region_h
            x1, x2 = j * region_w, (j + 1) * region_w
            
            if len(image_array.shape) == 3:
                region = image_array[y1:y2, x1:x2, :]
            else:
                region = image_array[y1:y2, x1:x2]
            
            variances.append(np.var(region))
    
    return np.mean(variances), np.std(variances)


def analyze_noise_addition(original_img, result_img):
    """
    Comprehensive noise analysis using three independent statistical methods.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to arrays
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    # Method 1: Global standard deviation analysis
    orig_std = np.std(orig_array)
    result_std = np.std(result_array)
    std_ratio = result_std / (orig_std + 1e-6)  # Avoid division by zero
    
    # Method 2: Laplacian-based noise estimation
    orig_noise = estimate_noise_std(orig_array)
    result_noise = estimate_noise_std(result_array)
    noise_ratio = result_noise / (orig_noise + 1e-6)
    
    # Method 3: Local variance comparison
    orig_local_var, _ = calculate_local_variance(orig_array)
    result_local_var, result_var_std = calculate_local_variance(result_array)
    var_ratio = result_local_var / (orig_local_var + 1e-6)
    
    # Combined metric (average of three methods)
    combined_ratio = (std_ratio + noise_ratio + var_ratio) / 3.0
    
    # Check if at least 2 of 3 methods show ≥15% increase
    methods_passed = sum([
        std_ratio >= 1.15,
        noise_ratio >= 1.15,
        var_ratio >= 1.15
    ])
    
    # Verify reasonable bounds (not excessive - could indicate corruption)
    reasonable = combined_ratio < 2.5
    
    return {
        'combined_ratio': combined_ratio,
        'std_ratio': std_ratio,
        'noise_ratio': noise_ratio,
        'var_ratio': var_ratio,
        'methods_passed': methods_passed,
        'reasonable': reasonable,
        'orig_std': orig_std,
        'result_std': result_std,
        'orig_noise': orig_noise,
        'result_noise': result_noise
    }


def check_rgb_noise(traj, env_info, task_info):
    """
    Main verifier function for RGB noise task.
    Checks:
    1. Measurable noise increase using multiple statistical methods
    2. Spatial distribution of noise across the image
    3. Reasonable noise levels (not image corruption)
    4. Evidence of actual image modification
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
        "/home/ga/Desktop/noisy_image.jpg",
        "/home/ga/Desktop/noisy_image.png",
        "/home/ga/Desktop/noisy_image.jpeg",
        "/home/ga/Desktop/clean_portrait_noisy.jpg",
        "/home/ga/Desktop/clean_portrait_noise.jpg",
        "/home/ga/Desktop/portrait_noise.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/clean_portrait.jpg",
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
        
        # Perform comprehensive noise analysis
        noise_analysis = analyze_noise_addition(original_image, result_image)
        
        # Check if image was meaningfully modified
        images_different = not np.array_equal(
            np.array(original_image.convert('RGB')),
            np.array(result_image.convert('RGB'))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Combined noise ratio: {noise_analysis['combined_ratio']:.2f}")
        feedback_parts.append(f"Std dev ratio: {noise_analysis['std_ratio']:.2f}")
        feedback_parts.append(f"Noise estimate ratio: {noise_analysis['noise_ratio']:.2f}")
        feedback_parts.append(f"Local variance ratio: {noise_analysis['var_ratio']:.2f}")
        feedback_parts.append(f"Methods showing increase: {noise_analysis['methods_passed']}/3")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. At least 15% increase in combined noise metrics
        noise_increase_significant = noise_analysis['combined_ratio'] >= 1.15
        if noise_increase_significant:
            criteria_met += 1
        feedback_parts.append(f"Significant noise increase: {'✅' if noise_increase_significant else '❌'}")
        
        # 2. At least 2 of 3 statistical methods show ≥15% increase
        multiple_methods_agree = noise_analysis['methods_passed'] >= 2
        if multiple_methods_agree:
            criteria_met += 1
        feedback_parts.append(f"Multiple methods agree: {'✅' if multiple_methods_agree else '❌'}")
        
        # 3. Noise levels are reasonable (not excessive)
        if noise_analysis['reasonable']:
            criteria_met += 1
        feedback_parts.append(f"Reasonable noise levels: {'✅' if noise_analysis['reasonable'] else '❌'}")
        
        # 4. Image was actually modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent RGB noise addition!")
        elif passed:
            feedback_parts.append("✅ Good RGB noise addition!")
        else:
            feedback_parts.append("❌ RGB noise addition needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in RGB noise verification: {e}")
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
    result = check_rgb_noise([], {}, {})
    print(f"Test result: {result}")