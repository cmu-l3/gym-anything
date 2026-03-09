#!/usr/bin/env python3
"""
Verifier for GIMP offset wrap-around task.
Checks if image was offset by 100px horizontally and 80px vertically with wrap-around.
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


def generate_offset_reference(original_img, offset_x, offset_y):
    """
    Generate perfect reference by applying offset with wrap-around using numpy roll.
    """
    # Convert image to numpy array
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    
    img_array = np.array(original_img)
    
    # Apply offset with wrap-around using numpy roll
    # Roll vertically first (axis=0), then horizontally (axis=1)
    offset_array = np.roll(img_array, shift=offset_y, axis=0)  # Y offset (vertical)
    offset_array = np.roll(offset_array, shift=offset_x, axis=1)  # X offset (horizontal)
    
    # Convert back to PIL Image
    return Image.fromarray(offset_array.astype('uint8'))


def check_offset_accuracy(original_img, result_img, offset_x=100, offset_y=80):
    """
    Check if the result image matches the expected offset with wrap-around.
    """
    # Generate reference offset image
    reference_img = generate_offset_reference(original_img, offset_x, offset_y)
    
    # Ensure result image is same size as reference
    if result_img.size != reference_img.size:
        result_img = result_img.resize(reference_img.size)
    
    # Ensure both are in RGB mode
    if reference_img.mode != 'RGB':
        reference_img = reference_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to arrays for comparison
    ref_array = np.array(reference_img)
    result_array = np.array(result_img)
    
    # Calculate Structural Similarity
    try:
        from skimage.metrics import structural_similarity as ssim
        ssim_score = ssim(ref_array, result_array, multichannel=True, channel_axis=2)
    except ImportError:
        try:
            from skimage.measure import compare_ssim as ssim
            ssim_score = ssim(ref_array, result_array, multichannel=True)
        except ImportError:
            # Fallback to simple pixel comparison
            diff = np.mean(np.abs(ref_array.astype(float) - result_array.astype(float)))
            # Convert difference to similarity score (lower diff = higher similarity)
            ssim_score = max(0, 1.0 - (diff / 255.0))
    
    return ssim_score, reference_img


def check_wrap_around_mode(original_img, result_img):
    """
    Check if wrap-around mode was used (not background fill mode).
    Wrap-around should preserve all original colors and not introduce black/white areas.
    """
    # Convert to arrays
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Check if result has significantly more black or white pixels than original
    orig_black_pixels = np.sum(np.all(orig_array < 20, axis=2))  # Very dark pixels
    orig_white_pixels = np.sum(np.all(orig_array > 235, axis=2))  # Very bright pixels
    
    result_black_pixels = np.sum(np.all(result_array < 20, axis=2))
    result_white_pixels = np.sum(np.all(result_array > 235, axis=2))
    
    # If result has significantly more black/white pixels, likely background fill was used
    black_increase = result_black_pixels - orig_black_pixels
    white_increase = result_white_pixels - orig_white_pixels
    
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    black_increase_ratio = black_increase / total_pixels
    white_increase_ratio = white_increase / total_pixels
    
    # Threshold: if more than 5% increase in pure black/white, likely background fill
    wrap_around_used = black_increase_ratio < 0.05 and white_increase_ratio < 0.05
    
    return wrap_around_used, black_increase_ratio, white_increase_ratio


def detect_boundary_continuity(original_img, result_img):
    """
    Check if content from opposite edges meets correctly at boundaries (wrap-around behavior).
    """
    if result_img.size != original_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    height, width = orig_array.shape[:2]
    
    # Sample pixels from edges to check continuity
    # Check if left edge of result matches right edge of original (after offset)
    # Check if top edge of result matches bottom edge of original (after offset)
    
    # For simplicity, check a few sample points along edges
    edge_samples = 5
    continuity_score = 0
    total_checks = 0
    
    # Check horizontal wrap (left-right continuity)
    for i in range(0, height, height // edge_samples):
        if i < height:
            # Left edge of result should contain content from right area of original
            result_left_pixel = result_array[i, 0]  # Left edge of result
            
            # In wrap-around, this should come from original[i, width-100] (shifted by offset_x=100)
            orig_source_x = (0 - 100) % width  # Where left edge content came from
            orig_source_pixel = orig_array[i, orig_source_x]
            
            # Calculate similarity
            pixel_diff = np.mean(np.abs(result_left_pixel.astype(float) - orig_source_pixel.astype(float)))
            if pixel_diff < 30:  # Threshold for similar pixels
                continuity_score += 1
            total_checks += 1
    
    # Check vertical wrap (top-bottom continuity)  
    for j in range(0, width, width // edge_samples):
        if j < width:
            # Top edge of result should contain content from bottom area of original
            result_top_pixel = result_array[0, j]  # Top edge of result
            
            # In wrap-around, this should come from original[height-80, j] (shifted by offset_y=80)
            orig_source_y = (0 - 80) % height  # Where top edge content came from
            orig_source_pixel = orig_array[orig_source_y, j]
            
            # Calculate similarity
            pixel_diff = np.mean(np.abs(result_top_pixel.astype(float) - orig_source_pixel.astype(float)))
            if pixel_diff < 30:  # Threshold for similar pixels
                continuity_score += 1
            total_checks += 1
    
    continuity_ratio = continuity_score / total_checks if total_checks > 0 else 0
    return continuity_ratio > 0.6  # At least 60% of edge samples should show continuity


def check_offset_wrap(traj, env_info, task_info):
    """
    Main verifier function for offset wrap-around task.
    Checks:
    1. Image was offset by correct amounts (100px X, 80px Y)
    2. Wrap-around mode was used (not background fill)
    3. Content is properly wrapped at boundaries
    4. Image dimensions are preserved
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
        "/home/ga/Desktop/offset_result.jpg",
        "/home/ga/Desktop/offset_result.png", 
        "/home/ga/Desktop/offset_result.jpeg",
        "/home/ga/Desktop/pattern_texture_offset.jpg",
        "/home/ga/Desktop/pattern_offset.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/pattern_texture.jpg",
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
        
        # Check offset accuracy using SSIM with reference
        ssim_score, reference_image = check_offset_accuracy(original_image, result_image, 100, 80)
        
        # Check if wrap-around mode was used
        wrap_around_used, black_increase, white_increase = check_wrap_around_mode(original_image, result_image)
        
        # Check boundary continuity
        boundary_continuity = detect_boundary_continuity(original_image, result_image)
        
        # Check if dimensions are preserved
        dimensions_preserved = original_image.size == result_image.size
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"SSIM with reference offset: {ssim_score:.3f}")
        feedback_parts.append(f"Offset accuracy (SSIM ≥ 0.95): {'✅' if ssim_score >= 0.95 else '❌'}")
        feedback_parts.append(f"Wrap-around mode used: {'✅' if wrap_around_used else '❌'}")
        feedback_parts.append(f"Boundary continuity: {'✅' if boundary_continuity else '❌'}")
        feedback_parts.append(f"Dimensions preserved: {'✅' if dimensions_preserved else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        if not wrap_around_used:
            feedback_parts.append(f"Black increase: {black_increase:.2%}, White increase: {white_increase:.2%}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        if ssim_score >= 0.95:  # Accurate offset
            criteria_met += 1
        if wrap_around_used:  # Correct mode
            criteria_met += 1
        if boundary_continuity:  # Proper wrap behavior
            criteria_met += 1
        if dimensions_preserved:  # Size maintained
            criteria_met += 1
        if images_different:  # Actually changed
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (or 3/5 with high scores)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect offset with wrap-around!")
        elif passed:
            feedback_parts.append("✅ Good offset with wrap-around!")
        else:
            feedback_parts.append("❌ Offset wrap-around needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in offset wrap verification: {e}")
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
    result = check_offset_wrap([], {}, {})
    print(f"Test result: {result}")