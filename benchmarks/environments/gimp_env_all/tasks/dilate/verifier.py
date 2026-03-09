#!/usr/bin/env python3
"""
Verifier for GIMP dilate morphological filter task.
Checks if the dilate filter was applied correctly to expand bright regions.
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


def analyze_brightness_expansion(original_img, result_img):
    """
    Analyze expansion of bright regions using multiple brightness thresholds.
    """
    # Convert to grayscale for analysis
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
    
    # Count pixels at various brightness thresholds
    thresholds = [200, 180, 160, 140]  # Different brightness levels
    brightness_changes = {}
    
    for thresh in thresholds:
        orig_bright = np.sum(orig_array > thresh)
        result_bright = np.sum(result_array > thresh)
        
        if orig_bright > 0:
            relative_change = (result_bright - orig_bright) / orig_bright
        else:
            relative_change = 0
        
        brightness_changes[thresh] = {
            'original': orig_bright,
            'result': result_bright,
            'absolute_change': result_bright - orig_bright,
            'relative_change': relative_change
        }
    
    # Overall brightness analysis
    orig_mean = np.mean(orig_array)
    result_mean = np.mean(result_array)
    brightness_increase = (result_mean - orig_mean) / orig_mean if orig_mean > 0 else 0
    
    return brightness_changes, brightness_increase


def analyze_edge_expansion(original_img, result_img):
    """
    Analyze edge thickening using gradient-based edge detection.
    """
    # Convert to grayscale arrays
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
    
    orig_array = np.array(original_gray, dtype=np.float32)
    result_array = np.array(result_gray, dtype=np.float32)
    
    # Simple edge detection using gradients
    def compute_edges(img_array):
        # Sobel-like edge detection
        gy, gx = np.gradient(img_array)
        magnitude = np.sqrt(gx**2 + gy**2)
        return magnitude
    
    try:
        # Try scipy for more accurate edge detection
        from scipy.ndimage import sobel
        
        orig_edges_x = sobel(orig_array, axis=1)
        orig_edges_y = sobel(orig_array, axis=0)
        orig_edges = np.hypot(orig_edges_x, orig_edges_y)
        
        result_edges_x = sobel(result_array, axis=1)
        result_edges_y = sobel(result_array, axis=0)
        result_edges = np.hypot(result_edges_x, result_edges_y)
        
    except ImportError:
        # Fallback to simple gradient method
        orig_edges = compute_edges(orig_array)
        result_edges = compute_edges(result_array)
    
    # Compare edge magnitudes
    orig_edge_sum = np.sum(orig_edges)
    result_edge_sum = np.sum(result_edges)
    
    edge_expansion = result_edge_sum > orig_edge_sum
    edge_ratio = result_edge_sum / orig_edge_sum if orig_edge_sum > 0 else 1
    
    return edge_expansion, edge_ratio, orig_edge_sum, result_edge_sum


def check_meaningful_change(original_img, result_img):
    """
    Check if images are meaningfully different (indicating filter was applied).
    """
    # Ensure same size and mode
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Convert to arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    if len(orig_array.shape) == 3:  # Color image
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        magnitude = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Count significantly changed pixels
    significant_change_threshold = 10  # Pixels changed by >10 intensity units
    significant_changes = np.sum(magnitude > significant_change_threshold)
    total_pixels = magnitude.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    return change_percentage, np.mean(magnitude)


def check_dilate_effect(traj, env_info, task_info):
    """
    Main verifier function for dilate morphological filter task.
    Checks:
    1. Bright regions expanded (increased high-intensity pixel count)
    2. Overall brightness increased
    3. Edges became thicker (increased edge magnitude)
    4. Image was meaningfully modified
    5. Changes consistent with morphological dilation
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
        "/home/ga/Desktop/dilated_image.png",
        "/home/ga/Desktop/dilated_image.jpg",
        "/home/ga/Desktop/dilated_image.jpeg",
        "/home/ga/Desktop/edge_image_dilated.png",
        "/home/ga/Desktop/edge_image_processed.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/edge_image.jpg",
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
        
        # Analyze brightness expansion
        brightness_changes, overall_brightness_increase = analyze_brightness_expansion(original_image, result_image)
        
        # Analyze edge expansion
        edge_expansion, edge_ratio, orig_edge_sum, result_edge_sum = analyze_edge_expansion(original_image, result_image)
        
        # Check meaningful change
        change_percentage, mean_change = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Overall brightness increase: {overall_brightness_increase:.3f}")
        feedback_parts.append(f"Pixels changed: {change_percentage:.1f}%")
        feedback_parts.append(f"Edge expansion detected: {'✅' if edge_expansion else '❌'}")
        feedback_parts.append(f"Edge ratio: {edge_ratio:.3f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Bright region expansion - check if bright pixels increased at any threshold
        bright_expansion_detected = False
        for thresh, changes in brightness_changes.items():
            if changes['relative_change'] > 0.01:  # 1% increase
                bright_expansion_detected = True
                break
        
        if bright_expansion_detected:
            criteria_met += 1
        feedback_parts.append(f"Bright region expansion: {'✅' if bright_expansion_detected else '❌'}")
        
        # 2. Overall brightness increase (even small increase indicates dilation)
        brightness_increased = overall_brightness_increase > 0.005  # 0.5% increase
        if brightness_increased:
            criteria_met += 1
        feedback_parts.append(f"Overall brightness increased: {'✅' if brightness_increased else '❌'}")
        
        # 3. Edge expansion (edges should become thicker/stronger)
        if edge_expansion:
            criteria_met += 1
        
        # 4. Meaningful change (at least 2% of pixels changed)
        meaningful_change = change_percentage > 2.0
        if meaningful_change:
            criteria_met += 1
        feedback_parts.append(f"Meaningful change: {'✅' if meaningful_change else '❌'}")
        
        # 5. Morphological consistency (changes should be expansive, not random)
        morphological_consistent = (bright_expansion_detected or brightness_increased) and meaningful_change
        if morphological_consistent:
            criteria_met += 1
        feedback_parts.append(f"Morphological consistency: {'✅' if morphological_consistent else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) but we use 75% threshold
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent morphological dilation!")
        elif passed:
            feedback_parts.append("✅ Good dilate filter application!")
        else:
            feedback_parts.append("❌ Dilation effect not detected or insufficient")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in dilate verification: {e}")
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
    result = check_dilate_effect([], {}, {})
    print(f"Test result: {result}")