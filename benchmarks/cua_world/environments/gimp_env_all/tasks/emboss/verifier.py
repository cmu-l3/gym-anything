#!/usr/bin/env python3
"""
Verifier for GIMP emboss effect task.
Checks if image was transformed with emboss filter creating grayscale relief appearance.
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


def check_grayscale_conversion(image):
    """
    Check if image is mostly grayscale (characteristic of emboss effect).
    Returns True if ≥70% of pixels have R, G, B values within 15 units of each other.
    """
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    img_array = np.array(image)
    r, g, b = img_array[:,:,0], img_array[:,:,1], img_array[:,:,2]
    
    # Calculate differences between color channels
    rg_diff = np.abs(r.astype(float) - g.astype(float))
    gb_diff = np.abs(g.astype(float) - b.astype(float))
    rb_diff = np.abs(r.astype(float) - b.astype(float))
    
    # Count pixels where all channels are within 15 units (effectively grayscale)
    grayscale_mask = (rg_diff < 15) & (gb_diff < 15) & (rb_diff < 15)
    grayscale_pixels = np.sum(grayscale_mask)
    total_pixels = img_array.shape[0] * img_array.shape[1]
    
    grayscale_percentage = (grayscale_pixels / total_pixels) * 100
    
    logging.debug(f"Grayscale pixels: {grayscale_pixels}/{total_pixels} ({grayscale_percentage:.1f}%)")
    
    return grayscale_percentage >= 70, grayscale_percentage


def check_edge_enhancement(original_img, result_img):
    """
    Check if edges are enhanced in the result (characteristic of emboss).
    Uses Sobel edge detection to measure edge strength increase.
    """
    # Convert to grayscale for edge analysis
    orig_gray = np.array(original_img.convert('L'))
    result_gray = np.array(result_img.convert('L'))
    
    # Ensure same dimensions
    if orig_gray.shape != result_gray.shape:
        result_img_resized = result_img.resize(original_img.size)
        result_gray = np.array(result_img_resized.convert('L'))
    
    try:
        from scipy.ndimage import sobel
        
        # Calculate edge strength using Sobel operators
        orig_edges_x = sobel(orig_gray, axis=0)
        orig_edges_y = sobel(orig_gray, axis=1)
        orig_edges = np.hypot(orig_edges_x, orig_edges_y)
        
        result_edges_x = sobel(result_gray, axis=0)
        result_edges_y = sobel(result_gray, axis=1)
        result_edges = np.hypot(result_edges_x, result_edges_y)
        
        # Calculate mean edge strength
        orig_edge_strength = np.mean(orig_edges)
        result_edge_strength = np.mean(result_edges)
        
        # Edge enhancement should increase edge strength by at least 30%
        enhancement_ratio = result_edge_strength / max(orig_edge_strength, 1.0)
        enhanced = enhancement_ratio >= 1.30
        
        logging.debug(f"Original edge strength: {orig_edge_strength:.2f}")
        logging.debug(f"Result edge strength: {result_edge_strength:.2f}")
        logging.debug(f"Enhancement ratio: {enhancement_ratio:.2f}")
        
        return enhanced, enhancement_ratio
        
    except ImportError:
        # Fallback method using simple gradient if scipy not available
        logging.warning("scipy not available, using fallback edge detection")
        
        # Simple gradient calculation
        orig_grad_x = np.gradient(orig_gray, axis=1)
        orig_grad_y = np.gradient(orig_gray, axis=0)
        orig_grad_mag = np.sqrt(orig_grad_x**2 + orig_grad_y**2)
        
        result_grad_x = np.gradient(result_gray, axis=1)
        result_grad_y = np.gradient(result_gray, axis=0)
        result_grad_mag = np.sqrt(result_grad_x**2 + result_grad_y**2)
        
        orig_edge_strength = np.mean(orig_grad_mag)
        result_edge_strength = np.mean(result_grad_mag)
        
        enhancement_ratio = result_edge_strength / max(orig_edge_strength, 1.0)
        enhanced = enhancement_ratio >= 1.30
        
        return enhanced, enhancement_ratio


def check_midtone_concentration(image):
    """
    Check if image has concentrated midtone values (characteristic of emboss).
    Emboss typically produces many pixels in the middle gray range [80, 175].
    """
    img_gray = np.array(image.convert('L'))
    
    # Count pixels in middle gray range
    midtone_mask = (img_gray >= 80) & (img_gray <= 175)
    midtone_pixels = np.sum(midtone_mask)
    total_pixels = img_gray.size
    
    midtone_percentage = (midtone_pixels / total_pixels) * 100
    
    logging.debug(f"Midtone pixels (80-175): {midtone_pixels}/{total_pixels} ({midtone_percentage:.1f}%)")
    
    return midtone_percentage >= 60, midtone_percentage


def check_significant_modification(original_img, result_img):
    """
    Check if the image was significantly modified.
    At least 40% of pixels should change by more than 30 intensity units.
    """
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    # Calculate pixel-wise difference magnitude
    diff = np.abs(orig_array - result_array)
    diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Count significantly changed pixels (>30 intensity units difference)
    significantly_changed = diff_magnitude > 30
    changed_pixels = np.sum(significantly_changed)
    total_pixels = diff_magnitude.size
    
    change_percentage = (changed_pixels / total_pixels) * 100
    
    logging.debug(f"Significantly changed pixels: {changed_pixels}/{total_pixels} ({change_percentage:.1f}%)")
    
    return change_percentage >= 40, change_percentage


def check_emboss_effect(traj, env_info, task_info):
    """
    Main verifier function for emboss effect task.
    Checks:
    1. Image converted to mostly grayscale (≥70% grayscale pixels)
    2. Edge enhancement occurred (≥30% increase in edge strength)
    3. Midtone concentration present (≥60% pixels in middle gray range)
    4. Image significantly modified (≥40% pixels changed by >30 units)
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
        "/home/ga/Desktop/embossed_image.jpg",
        "/home/ga/Desktop/embossed_image.png",
        "/home/ga/Desktop/embossed_image.jpeg",
        "/home/ga/Desktop/detailed_photo_emboss.jpg",
        "/home/ga/Desktop/detailed_photo_embossed.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/detailed_photo.jpg",
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
        
        # Run all verification checks
        grayscale_ok, grayscale_pct = check_grayscale_conversion(result_image)
        edge_enhanced, edge_ratio = check_edge_enhancement(original_image, result_image)
        midtone_ok, midtone_pct = check_midtone_concentration(result_image)
        modified_ok, change_pct = check_significant_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Grayscale conversion: {'✅' if grayscale_ok else '❌'} ({grayscale_pct:.1f}%)")
        feedback_parts.append(f"Edge enhancement: {'✅' if edge_enhanced else '❌'} (ratio: {edge_ratio:.2f})")
        feedback_parts.append(f"Midtone concentration: {'✅' if midtone_ok else '❌'} ({midtone_pct:.1f}%)")
        feedback_parts.append(f"Image modified: {'✅' if modified_ok else '❌'} ({change_pct:.1f}%)")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if grayscale_ok:
            criteria_met += 1
        if edge_enhanced:
            criteria_met += 1 
        if midtone_ok:
            criteria_met += 1
        if modified_ok:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect emboss effect applied!")
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