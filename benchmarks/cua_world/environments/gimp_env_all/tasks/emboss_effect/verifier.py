#!/usr/bin/env python3
"""
Verifier for GIMP emboss effect task.
Checks if emboss filter was successfully applied to create 3D raised relief effect.
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

# Try to import OpenCV for advanced edge detection
try:
    import cv2
    HAS_CV2 = True
    logging.debug("OpenCV available for edge detection")
except ImportError:
    HAS_CV2 = False
    logging.debug("OpenCV not available, using basic edge detection")


def detect_edge_enhancement(original_img, result_img):
    """
    Detect edge enhancement by comparing edge strength between original and result.
    Returns ratio of edge enhancement.
    """
    # Convert to grayscale for edge detection
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
        
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Ensure same size
    if original_img.size != result_img.size:
        result_gray = result_gray.resize(original_img.size)
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    if HAS_CV2:
        # Use Sobel operator for edge detection
        orig_edges = cv2.Sobel(orig_array, cv2.CV_64F, 1, 1, ksize=3)
        result_edges = cv2.Sobel(result_array, cv2.CV_64F, 1, 1, ksize=3)
        
        orig_edge_strength = np.mean(np.abs(orig_edges))
        result_edge_strength = np.mean(np.abs(result_edges))
    else:
        # Basic edge detection using gradient
        orig_grad_x = np.diff(orig_array, axis=1)
        orig_grad_y = np.diff(orig_array, axis=0)
        orig_edge_strength = np.mean(np.abs(orig_grad_x)) + np.mean(np.abs(orig_grad_y))
        
        result_grad_x = np.diff(result_array, axis=1)
        result_grad_y = np.diff(result_array, axis=0)
        result_edge_strength = np.mean(np.abs(result_grad_x)) + np.mean(np.abs(result_grad_y))
    
    # Calculate enhancement ratio
    if orig_edge_strength > 0:
        enhancement_ratio = result_edge_strength / orig_edge_strength
    else:
        enhancement_ratio = 1.0
        
    return {
        'orig_edge_strength': orig_edge_strength,
        'result_edge_strength': result_edge_strength,
        'enhancement_ratio': enhancement_ratio,
        'enhanced': enhancement_ratio >= 1.5
    }


def analyze_desaturation(original_img, result_img):
    """
    Analyze color desaturation - emboss typically reduces color saturation significantly.
    """
    # Convert to RGB for color analysis
    if original_img.mode != 'RGB':
        orig_rgb = original_img.convert('RGB')
    else:
        orig_rgb = original_img
        
    if result_img.mode != 'RGB':
        result_rgb = result_img.convert('RGB')
    else:
        result_rgb = result_img
    
    # Ensure same size
    if original_img.size != result_img.size:
        result_rgb = result_rgb.resize(original_img.size)
    
    orig_array = np.array(orig_rgb)
    result_array = np.array(result_rgb)
    
    if HAS_CV2:
        # Use HSV color space for saturation analysis
        orig_hsv = cv2.cvtColor(orig_array, cv2.COLOR_RGB2HSV)
        result_hsv = cv2.cvtColor(result_array, cv2.COLOR_RGB2HSV)
        
        orig_saturation = np.mean(orig_hsv[:,:,1]) / 255.0
        result_saturation = np.mean(result_hsv[:,:,1]) / 255.0
    else:
        # Basic saturation calculation using RGB
        def rgb_to_saturation(rgb_array):
            r, g, b = rgb_array[:,:,0], rgb_array[:,:,1], rgb_array[:,:,2]
            max_val = np.maximum(np.maximum(r, g), b)
            min_val = np.minimum(np.minimum(r, g), b)
            saturation = np.where(max_val > 0, (max_val - min_val) / max_val, 0)
            return np.mean(saturation)
        
        orig_saturation = rgb_to_saturation(orig_array / 255.0)
        result_saturation = rgb_to_saturation(result_array / 255.0)
    
    # Calculate saturation reduction percentage
    if orig_saturation > 0:
        saturation_reduction = ((orig_saturation - result_saturation) / orig_saturation) * 100
    else:
        saturation_reduction = 0
        
    return {
        'orig_saturation': orig_saturation,
        'result_saturation': result_saturation,
        'saturation_reduction_pct': saturation_reduction,
        'desaturated': saturation_reduction >= 40.0
    }


def check_relief_characteristics(result_img):
    """
    Check for characteristics of emboss/relief effect.
    """
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    result_array = np.array(result_gray)
    
    # Check for midtone dominance (emboss typically has prominent middle grays)
    histogram, _ = np.histogram(result_array, bins=256, range=(0, 256))
    midtone_range = histogram[96:160]  # Middle gray range
    total_pixels = np.sum(histogram)
    midtone_dominance = np.sum(midtone_range) / total_pixels if total_pixels > 0 else 0
    
    # Check local contrast (emboss has high local contrast around edges)
    local_contrast = np.std(result_array) / 255.0
    
    return {
        'midtone_dominance': midtone_dominance,
        'local_contrast': local_contrast,
        'relief_pattern': midtone_dominance > 0.3 and local_contrast > 0.2
    }


def check_meaningful_change(original_img, result_img):
    """
    Check if the images are meaningfully different.
    """
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    if len(orig_array.shape) == 3:  # Color image
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        significant_changes = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)
    else:  # Grayscale
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        significant_changes = np.sum(diff > 30)
    
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'substantial_change': mean_diff >= 20.0
    }


def check_emboss_effect(traj, env_info, task_info):
    """
    Main verifier function for emboss effect task.
    Checks:
    1. Strong edge enhancement (≥1.5x increase)
    2. Significant desaturation (≥40% reduction)
    3. Relief appearance characteristics
    4. Substantial image change
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
        "/home/ga/Desktop/embossed_output.jpg",
        "/home/ga/Desktop/embossed_output.png", 
        "/home/ga/Desktop/embossed_output.jpeg",
        "/home/ga/Desktop/emboss_output.jpg",
        "/home/ga/Desktop/emboss_input_embossed.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/emboss_input.jpg",
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
        
        # Perform emboss analysis
        edge_analysis = detect_edge_enhancement(original_image, result_image)
        saturation_analysis = analyze_desaturation(original_image, result_image)
        relief_analysis = check_relief_characteristics(result_image)
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge enhancement ratio: {edge_analysis['enhancement_ratio']:.2f}")
        feedback_parts.append(f"Saturation reduction: {saturation_analysis['saturation_reduction_pct']:.1f}%")
        feedback_parts.append(f"Mean pixel difference: {change_analysis['mean_difference']:.1f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Strong edge enhancement (≥1.5x increase)
        if edge_analysis['enhanced']:
            criteria_met += 1
        feedback_parts.append(f"Edge enhancement ≥1.5x: {'✅' if edge_analysis['enhanced'] else '❌'}")
        
        # 2. Significant desaturation (≥40% reduction)
        if saturation_analysis['desaturated']:
            criteria_met += 1
        feedback_parts.append(f"Desaturated ≥40%: {'✅' if saturation_analysis['desaturated'] else '❌'}")
        
        # 3. Relief appearance characteristics
        if relief_analysis['relief_pattern']:
            criteria_met += 1
        feedback_parts.append(f"Relief pattern detected: {'✅' if relief_analysis['relief_pattern'] else '❌'}")
        
        # 4. Substantial change
        if change_analysis['substantial_change']:
            criteria_met += 1
        feedback_parts.append(f"Substantial change: {'✅' if change_analysis['substantial_change'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent emboss effect applied!")
        elif passed:
            feedback_parts.append("✅ Good emboss effect!")
        else:
            feedback_parts.append("❌ Emboss effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in emboss verification: {e}")
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
    result = check_emboss_effect([], {}, {})
    print(f"Test result: {result}")