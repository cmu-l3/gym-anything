#!/usr/bin/env python3
"""
Verifier for GIMP edge detection task.
Checks if edge detection filter was successfully applied to the image.
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


def compute_edge_intensity(image_array):
    """
    Measure average edge strength using Sobel operators.
    Returns the mean edge magnitude across the image.
    """
    try:
        from scipy.ndimage import sobel
        has_scipy = True
    except ImportError:
        has_scipy = False
        logging.warning("SciPy not available, using fallback edge detection")
    
    # Convert to grayscale for edge computation
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    if has_scipy:
        # Use SciPy Sobel operators for precise edge detection
        gradient_x = sobel(gray, axis=0)
        gradient_y = sobel(gray, axis=1)
        edge_magnitude = np.sqrt(gradient_x**2 + gradient_y**2)
    else:
        # Fallback: simple difference-based edge detection
        grad_x = np.diff(gray, axis=0, prepend=gray[0:1, :])
        grad_y = np.diff(gray, axis=1, prepend=gray[:, 0:1])
        edge_magnitude = np.sqrt(grad_x**2 + grad_y**2)
    
    return np.mean(edge_magnitude)


def measure_background_suppression(image_array, dark_threshold=50):
    """
    Calculate percentage of dark (suppressed background) pixels.
    Edge detection should create many dark pixels where there were no edges.
    """
    if len(image_array.shape) == 3:
        gray = np.mean(image_array, axis=2)
    else:
        gray = image_array
    
    dark_pixels = np.sum(gray < dark_threshold)
    total_pixels = gray.size
    
    return (dark_pixels / total_pixels) * 100


def analyze_contrast_change(original_array, result_array):
    """
    Analyze contrast changes between original and edge-detected image.
    Edge detection should typically increase overall contrast.
    """
    # Convert to grayscale for analysis
    if len(original_array.shape) == 3:
        orig_gray = np.mean(original_array, axis=2)
    else:
        orig_gray = original_array
    
    if len(result_array.shape) == 3:
        result_gray = np.mean(result_array, axis=2)
    else:
        result_gray = result_array
    
    orig_std = np.std(orig_gray)
    result_std = np.std(result_gray)
    
    # Calculate contrast enhancement ratio
    contrast_ratio = result_std / max(orig_std, 1.0)  # Avoid division by zero
    
    return {
        'original_contrast': orig_std,
        'result_contrast': result_std,
        'contrast_ratio': contrast_ratio,
        'contrast_increased': result_std > orig_std * 0.8  # Allow slight decrease due to background suppression
    }


def measure_pixel_changes(original_array, result_array):
    """
    Measure how much the image changed from original to result.
    Edge detection should create significant changes in most pixels.
    """
    # Ensure arrays are same size
    if original_array.shape != result_array.shape:
        # This shouldn't happen, but handle gracefully
        logging.warning(f"Array shape mismatch: {original_array.shape} vs {result_array.shape}")
        return {'change_percentage': 0, 'mean_difference': 0}
    
    # Calculate pixel-wise differences
    pixel_diff = np.abs(original_array.astype(np.float32) - result_array.astype(np.float32))
    
    if len(pixel_diff.shape) == 3:
        # For RGB images, calculate magnitude of change
        pixel_diff_magnitude = np.sqrt(np.sum(pixel_diff ** 2, axis=2))
    else:
        pixel_diff_magnitude = pixel_diff
    
    # Count significantly changed pixels (>30 intensity units change)
    significant_changes = np.sum(pixel_diff_magnitude > 30)
    total_pixels = pixel_diff_magnitude.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    mean_difference = np.mean(pixel_diff_magnitude)
    
    return {
        'change_percentage': change_percentage,
        'mean_difference': mean_difference,
        'significantly_changed': change_percentage >= 10  # At least 10% of pixels changed
    }


def check_edge_detection(traj, env_info, task_info):
    """
    Main verifier function for edge detection task.
    Checks:
    1. Edge intensity increased significantly (≥50% enhancement)
    2. Background was suppressed (≥20% more dark pixels)
    3. Contrast was maintained or enhanced 
    4. Image was substantially modified (≥10% pixels changed)
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
        "/home/ga/Desktop/edges_detected.jpg",
        "/home/ga/Desktop/edges_detected.png",
        "/home/ga/Desktop/edges_detected.jpeg",
        "/home/ga/Desktop/sample_image_edges.jpg",
        "/home/ga/Desktop/sample_edge_detected.jpg",
        "/home/ga/Desktop/edge_result.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/sample_image.jpg",
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
        
        # Convert images to arrays for analysis
        orig_array = np.array(original_image.convert('RGB'))
        result_array = np.array(result_image.convert('RGB'))
        
        # Perform all analysis
        orig_edge_intensity = compute_edge_intensity(orig_array)
        result_edge_intensity = compute_edge_intensity(result_array)
        
        orig_dark_percentage = measure_background_suppression(orig_array)
        result_dark_percentage = measure_background_suppression(result_array)
        
        contrast_analysis = analyze_contrast_change(orig_array, result_array)
        change_analysis = measure_pixel_changes(orig_array, result_array)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original edge intensity: {orig_edge_intensity:.1f}")
        feedback_parts.append(f"Result edge intensity: {result_edge_intensity:.1f}")
        feedback_parts.append(f"Original dark pixels: {orig_dark_percentage:.1f}%")
        feedback_parts.append(f"Result dark pixels: {result_dark_percentage:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Edge intensity increased by at least 50%
        edge_increase = (result_edge_intensity - orig_edge_intensity) / max(orig_edge_intensity, 0.1)
        edge_enhanced = edge_increase >= 0.5
        if edge_enhanced:
            criteria_met += 1
        feedback_parts.append(f"Edge intensity increased ≥50%: {'✅' if edge_enhanced else '❌'} ({edge_increase:.1%})")
        
        # 2. Background suppressed (at least 20% more dark pixels)
        dark_increase = result_dark_percentage - orig_dark_percentage
        background_suppressed = dark_increase >= 20
        if background_suppressed:
            criteria_met += 1
        feedback_parts.append(f"Background suppressed ≥20pp: {'✅' if background_suppressed else '❌'} ({dark_increase:.1f}pp)")
        
        # 3. Contrast maintained or enhanced
        contrast_good = contrast_analysis['contrast_increased']
        if contrast_good:
            criteria_met += 1
        feedback_parts.append(f"Contrast maintained: {'✅' if contrast_good else '❌'} (ratio: {contrast_analysis['contrast_ratio']:.2f})")
        
        # 4. Image substantially modified
        substantially_changed = change_analysis['significantly_changed']
        if substantially_changed:
            criteria_met += 1
        feedback_parts.append(f"Substantially modified: {'✅' if substantially_changed else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect edge detection!")
        elif passed:
            feedback_parts.append("✅ Good edge detection!")
        else:
            feedback_parts.append("❌ Edge detection needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in edge detection verification: {e}")
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
    result = check_edge_detection([], {}, {})
    print(f"Test result: {result}")