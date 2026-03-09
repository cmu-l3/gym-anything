#!/usr/bin/env python3
"""
Verifier for GIMP noise reduction task.
Checks if noise was successfully reduced while preserving important details.
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


def measure_noise_level(image_array):
    """
    Measure noise by analyzing variance in smooth regions.
    Higher variance indicates more noise.
    """
    # Convert to grayscale for analysis
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    # Divide image into blocks and measure local variance
    block_size = 16
    variances = []
    
    for i in range(0, gray.shape[0] - block_size, block_size):
        for j in range(0, gray.shape[1] - block_size, block_size):
            block = gray[i:i+block_size, j:j+block_size]
            # Only consider relatively smooth blocks (low standard deviation)
            if np.std(block) < 50:  # Smooth region threshold
                variances.append(np.var(block))
    
    # Average variance in smooth regions indicates noise level
    return np.mean(variances) if variances else 0


def measure_edge_strength(image_array):
    """
    Measure image detail preservation using edge detection.
    Uses simple Sobel-like edge detection to measure detail level.
    """
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    # Simple edge detection using gradient
    # Sobel-like kernels for horizontal and vertical edges
    kernel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
    kernel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]])
    
    # Apply convolution manually (simple implementation)
    height, width = gray.shape
    edge_x = np.zeros_like(gray)
    edge_y = np.zeros_like(gray)
    
    for i in range(1, height - 1):
        for j in range(1, width - 1):
            # Apply kernel
            region = gray[i-1:i+2, j-1:j+2]
            edge_x[i, j] = np.sum(region * kernel_x)
            edge_y[i, j] = np.sum(region * kernel_y)
    
    # Calculate edge magnitude
    edge_magnitude = np.sqrt(edge_x**2 + edge_y**2)
    
    # Return average edge strength (indicates detail level)
    return np.mean(edge_magnitude)


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Convert to arrays for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 15)  # Pixels with >15 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed
    }


def verify_noise_reduction(original_img, result_img):
    """
    Comprehensive verification of noise reduction quality.
    Measures both noise reduction and detail preservation.
    """
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Ensure same size for comparison
    if orig_array.shape != result_array.shape:
        result_img = result_img.resize(original_img.size)
        result_array = np.array(result_img.convert('RGB'))
    
    # Measure noise levels in smooth regions
    orig_noise = measure_noise_level(orig_array)
    result_noise = measure_noise_level(result_array)
    noise_reduction_pct = ((orig_noise - result_noise) / orig_noise * 100) if orig_noise > 0 else 0
    
    # Measure detail preservation via edge strength
    orig_edges = measure_edge_strength(orig_array)
    result_edges = measure_edge_strength(result_array)
    detail_preservation_pct = (result_edges / orig_edges * 100) if orig_edges > 0 else 0
    
    # Check for meaningful changes
    change_analysis = check_meaningful_change(original_img, result_img)
    
    return {
        'orig_noise_level': orig_noise,
        'result_noise_level': result_noise,
        'noise_reduction_pct': noise_reduction_pct,
        'orig_edge_strength': orig_edges,
        'result_edge_strength': result_edges,
        'detail_preservation_pct': detail_preservation_pct,
        'change_analysis': change_analysis
    }


def check_noise_reduction(traj, env_info, task_info):
    """
    Main verifier function for noise reduction task.
    Checks:
    1. Noise was significantly reduced (≥15% reduction in variance)
    2. Details were preserved (≥85% edge strength retained)
    3. Image was meaningfully modified
    4. No severe over-smoothing occurred
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
        "/home/ga/Desktop/cleaned_image.jpg",
        "/home/ga/Desktop/cleaned_image.png",
        "/home/ga/Desktop/cleaned_image.jpeg",
        "/home/ga/Desktop/noisy_photo_cleaned.jpg",
        "/home/ga/Desktop/despeckled_image.jpg",
        "/home/ga/Desktop/filtered_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/noisy_photo.jpg",
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
        
        # Perform comprehensive noise reduction analysis
        analysis = verify_noise_reduction(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Noise reduction: {analysis['noise_reduction_pct']:.1f}%")
        feedback_parts.append(f"Detail preservation: {analysis['detail_preservation_pct']:.1f}%")
        feedback_parts.append(f"Pixels changed: {analysis['change_analysis']['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant noise reduction (at least 15% reduction in noise variance)
        noise_reduced_significantly = analysis['noise_reduction_pct'] >= 15.0
        if noise_reduced_significantly:
            criteria_met += 1
        feedback_parts.append(f"Noise reduced significantly: {'✅' if noise_reduced_significantly else '❌'}")
        
        # 2. Detail preservation (at least 85% edge strength retained)
        details_well_preserved = analysis['detail_preservation_pct'] >= 85.0
        if details_well_preserved:
            criteria_met += 1
        feedback_parts.append(f"Details well preserved: {'✅' if details_well_preserved else '❌'}")
        
        # 3. Meaningful change detected
        meaningfully_changed = analysis['change_analysis']['meaningfully_changed']
        if meaningfully_changed:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if meaningfully_changed else '❌'}")
        
        # 4. No severe over-smoothing (detail preservation shouldn't be too low)
        not_oversmoothed = analysis['detail_preservation_pct'] >= 70.0  # Looser threshold
        if not_oversmoothed:
            criteria_met += 1
        feedback_parts.append(f"Not over-smoothed: {'✅' if not_oversmoothed else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent noise reduction!")
        elif passed:
            feedback_parts.append("✅ Good noise reduction!")
        else:
            feedback_parts.append("❌ Noise reduction needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in noise reduction verification: {e}")
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
    result = check_noise_reduction([], {}, {})
    print(f"Test result: {result}")