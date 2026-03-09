#!/usr/bin/env python3
"""
Verifier for GIMP layer offset task.
Checks if layer content was offset with wrap-around mode.
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


def detect_offset_via_correlation(original_img, result_img):
    """
    Detect pixel offset using 2D cross-correlation.
    Returns offset_x, offset_y, and confidence score.
    """
    # Convert to grayscale for efficiency
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
        
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Ensure same size
    if orig_gray.size != result_gray.size:
        result_gray = result_gray.resize(orig_gray.size)
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    try:
        from scipy import signal
        
        # Compute normalized cross-correlation
        correlation = signal.correlate2d(result_array, orig_array, mode='same')
        
        # Find correlation peak (excluding center/zero offset)
        center_y, center_x = np.array(correlation.shape) // 2
        
        # Mask out the center region to avoid detecting zero offset
        mask_size = 5
        correlation[center_y-mask_size:center_y+mask_size, 
                   center_x-mask_size:center_x+mask_size] = 0
        
        # Find the peak correlation
        peak_y, peak_x = np.unravel_index(np.argmax(correlation), correlation.shape)
        
        # Calculate offset from center
        offset_y = peak_y - center_y
        offset_x = peak_x - center_x
        
        # Get confidence score (normalized correlation value)
        confidence = correlation[peak_y, peak_x] / (np.std(orig_array) * np.std(result_array) * orig_array.size)
        
        return offset_x, offset_y, confidence
        
    except ImportError:
        logging.warning("scipy not available, using fallback correlation method")
        # Simple fallback method using numpy
        height, width = orig_array.shape
        
        best_correlation = -1
        best_offset = (0, 0)
        
        # Test common offset values (quarters and halves)
        test_offsets = [
            (width//4, 0), (width//2, 0), (3*width//4, 0),
            (0, height//4), (0, height//2), (0, 3*height//4),
            (width//2, height//2), (width//4, height//4)
        ]
        
        for offset_x, offset_y in test_offsets:
            # Create expected offset image using numpy roll
            expected = np.roll(np.roll(orig_array, offset_x, axis=1), offset_y, axis=0)
            
            # Calculate correlation coefficient
            correlation = np.corrcoef(expected.flatten(), result_array.flatten())[0, 1]
            
            if correlation > best_correlation:
                best_correlation = correlation
                best_offset = (offset_x, offset_y)
        
        return best_offset[0], best_offset[1], best_correlation


def verify_wrap_around(original_img, result_img, offset_x, offset_y):
    """
    Verify that pixels wrapped correctly using modulo arithmetic.
    Returns match percentage and validation result.
    """
    # Ensure same size and format
    if result_img.size != original_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Generate expected wrapped image using numpy roll
    expected = np.roll(np.roll(orig_array, offset_x, axis=1), offset_y, axis=0)
    
    # Calculate pixel-wise difference
    if len(orig_array.shape) == 3:  # Color image
        difference = np.abs(expected.astype(np.float32) - result_array.astype(np.float32))
        difference_magnitude = np.sqrt(np.sum(difference ** 2, axis=2))
    else:  # Grayscale
        difference_magnitude = np.abs(expected.astype(np.float32) - result_array.astype(np.float32))
    
    # Allow small tolerance for compression artifacts
    tolerance = 10  # intensity units
    match_mask = difference_magnitude < tolerance
    match_percentage = np.mean(match_mask) * 100
    
    # Good wrap-around should have >90% pixel match
    is_valid_wrap = match_percentage >= 90
    
    return match_percentage, is_valid_wrap


def check_meaningful_offset(offset_x, offset_y, img_size):
    """
    Check if the detected offset is meaningful (not trivial).
    """
    width, height = img_size
    
    # Calculate offset magnitude as percentage of image dimensions
    x_percent = abs(offset_x) / width * 100 if width > 0 else 0
    y_percent = abs(offset_y) / height * 100 if height > 0 else 0
    
    # Offset should be at least 10% of image dimension to be meaningful
    meaningful_x = x_percent >= 10
    meaningful_y = y_percent >= 10
    
    # At least one dimension should have meaningful offset
    is_meaningful = meaningful_x or meaningful_y
    
    return is_meaningful, x_percent, y_percent


def check_layer_offset(traj, env_info, task_info):
    """
    Main verifier function for layer offset task.
    Checks:
    1. Significant offset was detected via cross-correlation
    2. Wrap-around mode was used (pixels wrapped correctly)
    3. Offset direction and magnitude are appropriate
    4. Image quality and dimensions preserved
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
        "/home/ga/Desktop/offset_texture.png",
        "/home/ga/Desktop/offset_texture.jpg", 
        "/home/ga/Desktop/offset_texture.jpeg",
        "/home/ga/Desktop/texture_offset.png",
        "/home/ga/Desktop/texture_pattern_offset.jpg",
        "/home/ga/Desktop/texture_pattern_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/texture_pattern.jpg",
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
        
        # Detect offset using cross-correlation
        offset_x, offset_y, correlation_confidence = detect_offset_via_correlation(original_image, result_image)
        
        # Check if offset is meaningful
        is_meaningful, x_percent, y_percent = check_meaningful_offset(offset_x, offset_y, original_image.size)
        
        # Verify wrap-around behavior
        wrap_match_percent, is_valid_wrap = verify_wrap_around(original_image, result_image, offset_x, offset_y)
        
        # Check if image dimensions were preserved
        dimensions_preserved = original_image.size == result_image.size
        
        # Check if image was actually modified (not identical)
        if original_image.size == result_image.size:
            orig_array = np.array(original_image)
            result_array = np.array(result_image.convert(original_image.mode))
            images_different = not np.array_equal(orig_array, result_array)
        else:
            images_different = True
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Detected offset: ({offset_x}, {offset_y})")
        feedback_parts.append(f"Offset magnitude: {x_percent:.1f}% x {y_percent:.1f}%")
        feedback_parts.append(f"Correlation confidence: {correlation_confidence:.3f}")
        feedback_parts.append(f"Wrap-around match: {wrap_match_percent:.1f}%")
        feedback_parts.append(f"Meaningful offset: {'✅' if is_meaningful else '❌'}")
        feedback_parts.append(f"Valid wrap-around: {'✅' if is_valid_wrap else '❌'}")
        feedback_parts.append(f"Dimensions preserved: {'✅' if dimensions_preserved else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Meaningful offset detected
        if is_meaningful and correlation_confidence > 0.5:
            criteria_met += 1
        
        # 2. Valid wrap-around mode (high pixel match percentage)
        if is_valid_wrap:
            criteria_met += 1
        
        # 3. Dimensions preserved
        if dimensions_preserved:
            criteria_met += 1
        
        # 4. Image was actually modified
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect layer offset with wrap-around!")
        elif passed:
            feedback_parts.append("✅ Good layer offset applied!")
        else:
            feedback_parts.append("❌ Layer offset needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in layer offset verification: {e}")
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
    result = check_layer_offset([], {}, {})
    print(f"Test result: {result}")