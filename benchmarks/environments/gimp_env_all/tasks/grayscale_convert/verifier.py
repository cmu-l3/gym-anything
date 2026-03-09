#!/usr/bin/env python3
"""
Verifier for GIMP grayscale conversion task.
Checks if color image was successfully converted to grayscale.
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


def verify_grayscale_conversion(img):
    """
    Verify that an image is in true grayscale (R=G=B for all pixels).
    Returns (is_grayscale, grayscale_percentage).
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Extract RGB channels
    r_channel = img_array[:, :, 0]
    g_channel = img_array[:, :, 1] 
    b_channel = img_array[:, :, 2]
    
    # Check if R = G = B for all pixels (true grayscale condition)
    # Allow small tolerance for compression artifacts
    tolerance = 2
    
    rg_match = np.abs(r_channel.astype(np.int16) - g_channel.astype(np.int16)) <= tolerance
    rb_match = np.abs(r_channel.astype(np.int16) - b_channel.astype(np.int16)) <= tolerance
    gb_match = np.abs(g_channel.astype(np.int16) - b_channel.astype(np.int16)) <= tolerance
    
    # All three channel pairs must match for true grayscale
    pixel_matches = rg_match & rb_match & gb_match
    grayscale_percentage = np.mean(pixel_matches) * 100
    
    # Consider it grayscale if 98%+ of pixels meet the criteria
    is_grayscale = grayscale_percentage >= 98.0
    
    return is_grayscale, grayscale_percentage


def detect_color_content(img):
    """
    Detect if image has significant color content by analyzing color variation.
    Returns (has_color, color_variance).
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Calculate variance between RGB channels
    r_channel = img_array[:, :, 0].astype(np.float32)
    g_channel = img_array[:, :, 1].astype(np.float32)
    b_channel = img_array[:, :, 2].astype(np.float32)
    
    # Calculate the standard deviation of RGB values for each pixel
    rgb_stack = np.stack([r_channel, g_channel, b_channel], axis=2)
    pixel_color_std = np.std(rgb_stack, axis=2)
    
    # Average standard deviation across all pixels
    avg_color_variance = np.mean(pixel_color_std)
    
    # If average variance > 5, there's likely significant color content
    has_color = avg_color_variance > 5.0
    
    return has_color, avg_color_variance


def check_image_modification(original_img, result_img):
    """Check if the image was meaningfully modified from original."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert both to same mode
    if original_img.mode != result_img.mode:
        if original_img.mode == 'RGB' or result_img.mode == 'RGB':
            original_img = original_img.convert('RGB')
            result_img = result_img.convert('RGB')
    
    # Compare arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate percentage of pixels that changed
    if orig_array.shape != result_array.shape:
        # If shapes don't match, assume modification occurred
        return True, 100.0
    
    pixel_differences = np.abs(orig_array.astype(np.int16) - result_array.astype(np.int16))
    
    # Sum differences across all channels
    if len(pixel_differences.shape) == 3:
        total_diff = np.sum(pixel_differences, axis=2)
    else:
        total_diff = pixel_differences
    
    # Count pixels with significant change (>10 intensity units)
    changed_pixels = np.sum(total_diff > 10)
    total_pixels = total_diff.size
    change_percentage = (changed_pixels / total_pixels) * 100
    
    # Consider modified if >5% of pixels changed significantly
    is_modified = change_percentage > 5.0
    
    return is_modified, change_percentage


def check_grayscale_conversion(traj, env_info, task_info):
    """
    Main verifier function for grayscale conversion task.
    Checks:
    1. Result image is in true grayscale (R=G=B for all pixels)
    2. Image was meaningfully modified from original
    3. Dimensions are preserved
    4. Image quality is maintained
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
        "/home/ga/Desktop/flower_grayscale.jpg",
        "/home/ga/Desktop/flower_grayscale.png",
        "/home/ga/Desktop/flower_grayscale.jpeg",
        "/home/ga/Desktop/flower_color_grayscale.jpg",
        "/home/ga/Desktop/grayscale_flower.jpg",
        "/home/ga/Desktop/flower_color_converted.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_color.jpg",
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
        
        # Check if result is in grayscale
        is_grayscale, grayscale_percentage = verify_grayscale_conversion(result_image)
        
        # Check if original had color content
        orig_has_color, orig_color_variance = detect_color_content(original_image)
        result_has_color, result_color_variance = detect_color_content(result_image)
        
        # Check if image was modified
        is_modified, change_percentage = check_image_modification(original_image, result_image)
        
        # Check if dimensions are preserved
        dimensions_preserved = original_image.size == result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original had color: {'Yes' if orig_has_color else 'No'} (variance: {orig_color_variance:.1f})")
        feedback_parts.append(f"Result has color: {'Yes' if result_has_color else 'No'} (variance: {result_color_variance:.1f})")
        feedback_parts.append(f"Grayscale pixels: {grayscale_percentage:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_percentage:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Perfect grayscale (R=G=B for all pixels)
        if is_grayscale:
            criteria_met += 1
        feedback_parts.append(f"Perfect grayscale: {'✅' if is_grayscale else '❌'}")
        
        # 2. Image was modified from original
        if is_modified:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if is_modified else '❌'}")
        
        # 3. Dimensions preserved
        if dimensions_preserved:
            criteria_met += 1
        feedback_parts.append(f"Dimensions preserved: {'✅' if dimensions_preserved else '❌'}")
        
        # 4. Color was successfully removed (result has less color than original)
        color_removed = (orig_has_color and not result_has_color) or (result_color_variance < orig_color_variance * 0.5)
        if color_removed:
            criteria_met += 1
        feedback_parts.append(f"Color removed: {'✅' if color_removed else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect grayscale conversion!")
        elif passed:
            feedback_parts.append("✅ Good grayscale conversion!")
        else:
            feedback_parts.append("❌ Grayscale conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in grayscale conversion verification: {e}")
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
    result = check_grayscale_conversion([], {}, {})
    print(f"Test result: {result}")