#!/usr/bin/env python3
"""
Verifier for GIMP soft glow effect task.
Checks if soft glow filter was successfully applied with appropriate brightness increase,
edge softening, and characteristic glow effects.
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


def analyze_brightness_change(original_img, result_img):
    """
    Analyze brightness changes between original and result images.
    Soft glow should increase overall brightness, especially in highlights.
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
    
    orig_array = np.array(original_gray, dtype=np.float32)
    result_array = np.array(result_gray, dtype=np.float32)
    
    # Calculate overall brightness increase
    orig_brightness = np.mean(orig_array)
    result_brightness = np.mean(result_array)
    brightness_increase = (result_brightness - orig_brightness) / orig_brightness
    
    # Analyze highlights (bright pixels > 180)
    orig_highlights = np.sum(orig_array > 180)
    result_highlights = np.sum(result_array > 180)
    highlight_expansion = result_highlights / max(orig_highlights, 1)
    
    # Analyze high-value pixels (> 200)
    orig_bright_pixels = np.sum(orig_array > 200)
    result_bright_pixels = np.sum(result_array > 200)
    bright_pixel_ratio = result_bright_pixels / max(orig_bright_pixels, 1)
    
    return {
        'original_brightness': orig_brightness,
        'result_brightness': result_brightness,
        'brightness_increase': brightness_increase,
        'highlight_expansion': highlight_expansion,
        'bright_pixel_ratio': bright_pixel_ratio,
        'brightness_increase_ok': 0.05 <= brightness_increase <= 0.30
    }


def analyze_edge_softness(original_img, result_img):
    """
    Analyze edge sharpness changes to detect softening effect.
    Soft glow should reduce edge sharpness through diffusion.
    """
    # Convert to grayscale
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
    
    # Calculate edge sharpness using gradient magnitude
    try:
        from scipy.ndimage import sobel
        
        # Calculate gradients
        orig_grad_x = sobel(orig_array, axis=1)
        orig_grad_y = sobel(orig_array, axis=0)
        orig_edges = np.hypot(orig_grad_x, orig_grad_y)
        
        result_grad_x = sobel(result_array, axis=1)
        result_grad_y = sobel(result_array, axis=0)
        result_edges = np.hypot(result_grad_x, result_grad_y)
        
        # Calculate average edge strength
        orig_sharpness = np.mean(orig_edges)
        result_sharpness = np.mean(result_edges)
        sharpness_reduction = (orig_sharpness - result_sharpness) / orig_sharpness
        
        return {
            'original_sharpness': orig_sharpness,
            'result_sharpness': result_sharpness,
            'sharpness_reduction': sharpness_reduction,
            'softness_ok': sharpness_reduction >= 0.15
        }
        
    except ImportError:
        # Fallback without scipy - use simple variance measure
        orig_variance = np.var(orig_array)
        result_variance = np.var(result_array)
        variance_reduction = (orig_variance - result_variance) / orig_variance
        
        return {
            'original_sharpness': orig_variance,
            'result_sharpness': result_variance,
            'sharpness_reduction': variance_reduction,
            'softness_ok': variance_reduction >= 0.10
        }


def detect_glow_characteristics(original_img, result_img):
    """
    Detect characteristic glow effects including highlight bloom and diffusion.
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
    
    orig_array = np.array(original_gray, dtype=np.float32)
    result_array = np.array(result_gray, dtype=np.float32)
    
    # Analyze highlight bloom (expansion of bright areas)
    orig_highlights = orig_array > 200
    result_highlights = result_array > 200
    
    orig_highlight_area = np.sum(orig_highlights)
    result_highlight_area = np.sum(result_highlights)
    
    if orig_highlight_area > 0:
        highlight_bloom_ratio = result_highlight_area / orig_highlight_area
    else:
        highlight_bloom_ratio = 1.0
    
    # Analyze variance changes (detail preservation)
    orig_variance = np.var(orig_array)
    result_variance = np.var(result_array)
    variance_change = (orig_variance - result_variance) / orig_variance
    
    # Check for appropriate glow characteristics
    good_bloom = 1.05 <= highlight_bloom_ratio <= 1.50  # 5-50% expansion
    good_variance = 0.05 <= variance_change <= 0.40     # Some softening but not total loss
    
    return {
        'highlight_bloom_ratio': highlight_bloom_ratio,
        'variance_change': variance_change,
        'original_variance': orig_variance,
        'result_variance': result_variance,
        'bloom_ok': good_bloom,
        'variance_ok': good_variance
    }


def check_image_modification(original_img, result_img):
    """Check if the image was meaningfully modified."""
    # Ensure same size and format
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Calculate pixel-wise differences
    orig_array = np.array(original_img, dtype=np.float32)
    result_array = np.array(result_img, dtype=np.float32)
    
    # Calculate mean absolute difference
    mean_diff = np.mean(np.abs(orig_array - result_array))
    
    # Calculate percentage of significantly changed pixels
    if len(orig_array.shape) == 3:  # RGB
        pixel_diff = np.sqrt(np.sum((orig_array - result_array) ** 2, axis=2))
    else:  # Grayscale
        pixel_diff = np.abs(orig_array - result_array)
    
    significant_changes = np.sum(pixel_diff > 20)  # Pixels changed by >20 intensity units
    total_pixels = pixel_diff.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 3  # At least 3% pixels changed
    }


def check_softglow_effect(traj, env_info, task_info):
    """
    Main verifier function for soft glow effect task.
    Checks:
    1. Image brightness increased appropriately (5-20%)
    2. Edges were softened (sharpness reduced by 15%+)
    3. Glow characteristics present (highlight bloom, variance changes)
    4. Image was meaningfully modified
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
        "/home/ga/Desktop/softglow_portrait.jpg",
        "/home/ga/Desktop/softglow_portrait.png",
        "/home/ga/Desktop/softglow_portrait.jpeg",
        "/home/ga/Desktop/portrait_softglow_edited.jpg",
        "/home/ga/Desktop/portrait_glow.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_softglow.jpg",
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
        
        # Perform all analyses
        brightness_analysis = analyze_brightness_change(original_image, result_image)
        softness_analysis = analyze_edge_softness(original_image, result_image)
        glow_analysis = detect_glow_characteristics(original_image, result_image)
        modification_analysis = check_image_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Brightness increase: {brightness_analysis['brightness_increase']:.1%}")
        feedback_parts.append(f"Sharpness reduction: {softness_analysis['sharpness_reduction']:.1%}")
        feedback_parts.append(f"Highlight bloom: {glow_analysis['highlight_bloom_ratio']:.2f}x")
        feedback_parts.append(f"Pixels changed: {modification_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Brightness increased appropriately
        if brightness_analysis['brightness_increase_ok']:
            criteria_met += 1
        feedback_parts.append(f"Brightness enhanced: {'✅' if brightness_analysis['brightness_increase_ok'] else '❌'}")
        
        # 2. Edges softened sufficiently
        if softness_analysis['softness_ok']:
            criteria_met += 1
        feedback_parts.append(f"Edges softened: {'✅' if softness_analysis['softness_ok'] else '❌'}")
        
        # 3. Glow characteristics present
        glow_present = glow_analysis['bloom_ok'] and glow_analysis['variance_ok']
        if glow_present:
            criteria_met += 1
        feedback_parts.append(f"Glow characteristics: {'✅' if glow_present else '❌'}")
        
        # 4. Image meaningfully modified
        if modification_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect soft glow effect!")
        elif passed:
            feedback_parts.append("✅ Good soft glow effect!")
        else:
            feedback_parts.append("❌ Soft glow effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in soft glow verification: {e}")
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
    result = check_softglow_effect([], {}, {})
    print(f"Test result: {result}")