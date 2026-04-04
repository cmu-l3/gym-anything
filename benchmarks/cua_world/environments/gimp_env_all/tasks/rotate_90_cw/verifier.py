#!/usr/bin/env python3
"""
Verifier for GIMP 90° clockwise rotation task.
Checks if image was rotated exactly 90° clockwise from landscape to portrait.
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


def verify_90_clockwise_rotation(original_img, result_img):
    """
    Verify that result image is a 90° clockwise rotation of original.
    Returns SSIM score and success status.
    """
    # Generate perfect 90° clockwise reference
    # Note: PIL's rotate() uses counter-clockwise angles, so -90 = clockwise 90°
    reference_rotation = original_img.rotate(-90, expand=True)
    
    # Ensure both images have same dimensions after rotation
    if reference_rotation.size != result_img.size:
        logging.debug(f"Dimension mismatch: reference {reference_rotation.size} vs result {result_img.size}")
        return False, 0.0, "Dimension mismatch after rotation"
    
    # Calculate structural similarity using SSIM
    try:
        from skimage.metrics import structural_similarity as ssim
        
        # Convert to RGB if needed
        if reference_rotation.mode != 'RGB':
            reference_rotation = reference_rotation.convert('RGB')
        if result_img.mode != 'RGB':
            result_img = result_img.convert('RGB')
        
        ref_array = np.array(reference_rotation)
        result_array = np.array(result_img)
        
        # Calculate SSIM
        ssim_score = ssim(ref_array, result_array, multichannel=True, channel_axis=2)
        
        # High threshold for rotation accuracy
        rotation_correct = ssim_score >= 0.95
        
        return rotation_correct, ssim_score, f"SSIM: {ssim_score:.3f}"
        
    except ImportError:
        # Fallback pixel comparison if skimage not available
        logging.warning("SSIM not available, using pixel comparison fallback")
        
        ref_array = np.array(reference_rotation.convert('RGB'))
        result_array = np.array(result_img.convert('RGB'))
        
        # Calculate pixel-wise differences
        diff = np.mean(np.abs(ref_array.astype(np.float32) - result_array.astype(np.float32)))
        similarity = max(0, 1 - (diff / 255.0))  # Normalize to 0-1
        
        rotation_correct = similarity >= 0.95
        return rotation_correct, similarity, f"Pixel similarity: {similarity:.3f}"


def verify_dimension_swap(original_img, result_img):
    """
    Verify that width and height have been properly swapped after 90° rotation.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # After 90° rotation, width should become height and vice versa
    expected_w, expected_h = orig_h, orig_w
    
    dimensions_swapped = (result_w == expected_w and result_h == expected_h)
    
    return dimensions_swapped, f"Original: {orig_w}x{orig_h} → Result: {result_w}x{result_h} (Expected: {expected_w}x{expected_h})"


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different (rotation occurred)."""
    # Resize result to match original if needed for comparison
    if original_img.size != result_img.size:
        # Don't resize - different size after rotation is expected
        return True, "Dimensions changed (rotation detected)"
    
    # Convert to arrays for comparison
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # Pixels with >30 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    meaningfully_changed = change_percentage > 10  # At least 10% of pixels changed
    
    return meaningfully_changed, f"Changed pixels: {change_percentage:.1f}%, Mean diff: {mean_diff:.1f}"


def check_rotation_90_cw(traj, env_info, task_info):
    """
    Main verifier function for 90° clockwise rotation task.
    Checks:
    1. Image was rotated exactly 90° clockwise
    2. Dimensions were properly swapped (landscape → portrait)
    3. Image quality was preserved
    4. Meaningful change occurred
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
        "/home/ga/Desktop/landscape_rotated_cw.jpg",
        "/home/ga/Desktop/landscape_rotated_cw.png",
        "/home/ga/Desktop/landscape_rotated_cw.jpeg",
        "/home/ga/Desktop/rotated_landscape.jpg",
        "/home/ga/Desktop/landscape_cw.jpg",
        "/home/ga/Desktop/landscape_image_rotated.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_image.jpg",
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
        
        # Verify 90° clockwise rotation
        rotation_correct, ssim_score, ssim_msg = verify_90_clockwise_rotation(original_image, result_image)
        
        # Verify dimension swap
        dimensions_swapped, dimension_msg = verify_dimension_swap(original_image, result_image)
        
        # Check for meaningful change
        meaningfully_changed, change_msg = check_meaningful_change(original_image, result_image)
        
        # Check quality preservation (similar dimensions after accounting for rotation)
        orig_area = original_image.size[0] * original_image.size[1]
        result_area = result_image.size[0] * result_image.size[1]
        area_preserved = abs(orig_area - result_area) < (orig_area * 0.05)  # Within 5%
        
        feedback_parts = []
        feedback_parts.append(dimension_msg)
        feedback_parts.append(ssim_msg)
        feedback_parts.append(change_msg)
        feedback_parts.append(f"90° clockwise rotation: {'✅' if rotation_correct else '❌'}")
        feedback_parts.append(f"Dimensions swapped: {'✅' if dimensions_swapped else '❌'}")
        feedback_parts.append(f"Area preserved: {'✅' if area_preserved else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if meaningfully_changed else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if rotation_correct:
            criteria_met += 1
        if dimensions_swapped:
            criteria_met += 1
        if area_preserved:
            criteria_met += 1
        if meaningfully_changed:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect 90° clockwise rotation!")
        elif passed:
            feedback_parts.append("✅ Good 90° clockwise rotation!")
        else:
            feedback_parts.append("❌ Rotation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rotation verification: {e}")
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
    result = check_rotation_90_cw([], {}, {})
    print(f"Test result: {result}")