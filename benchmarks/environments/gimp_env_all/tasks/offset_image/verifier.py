#!/usr/bin/env python3
"""
Verifier for GIMP image offset task.
Checks if image was offset by 150px right and 100px down with wrap-around.
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

try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
    except ImportError:
        logging.warning("scikit-image not available, using fallback comparison")
        ssim = None


def create_offset_reference(original_img, offset_x, offset_y):
    """
    Create reference image with exact offset and wrap-around using numpy roll.
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    
    img_array = np.array(original_img)
    
    # Apply wrap-around using NumPy roll
    # Roll in Y direction first (vertical shift)
    offset_array = np.roll(img_array, shift=offset_y, axis=0)
    
    # Roll in X direction (horizontal shift)  
    offset_array = np.roll(offset_array, shift=offset_x, axis=1)
    
    return Image.fromarray(offset_array.astype(np.uint8))


def verify_offset_with_ssim(original_img, result_img, expected_x=150, expected_y=100):
    """
    Verify offset was applied correctly using SSIM comparison with reference.
    """
    if ssim is None:
        return False, 0.0, "SSIM not available"
    
    # Ensure images are same size
    if original_img.size != result_img.size:
        return False, 0.0, f"Size mismatch: {original_img.size} vs {result_img.size}"
    
    # Generate perfect reference offset
    reference = create_offset_reference(original_img, expected_x, expected_y)
    
    # Convert to RGB if needed
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to arrays for SSIM
    ref_array = np.array(reference)
    result_array = np.array(result_img)
    
    # Calculate structural similarity
    try:
        # Try newer API first
        try:
            ssim_score = ssim(ref_array, result_array, multichannel=True, channel_axis=2)
        except TypeError:
            # Fallback to older API
            ssim_score = ssim(ref_array, result_array, multichannel=True)
    except Exception as e:
        return False, 0.0, f"SSIM calculation failed: {str(e)}"
    
    # High threshold for precise offset verification
    offset_successful = ssim_score >= 0.95
    
    return offset_successful, ssim_score, "SSIM calculation successful"


def verify_offset_fallback(original_img, result_img, expected_x=150, expected_y=100):
    """
    Fallback verification using direct pixel comparison when SSIM unavailable.
    """
    if original_img.size != result_img.size:
        return False, 0.0, "Size mismatch"
    
    # Generate reference offset
    reference = create_offset_reference(original_img, expected_x, expected_y)
    
    # Convert to arrays
    ref_array = np.array(reference.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(ref_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Check if images are very similar (low mean difference)
    similarity_score = max(0, 1 - (mean_diff / 100.0))  # Normalize to 0-1
    offset_successful = similarity_score >= 0.9
    
    return offset_successful, similarity_score, "Pixel comparison completed"


def check_meaningful_offset(original_img, result_img):
    """
    Check if the image was meaningfully modified from the original.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 15  # At least 15% of pixels changed
    }


def check_image_offset(traj, env_info, task_info):
    """
    Main verifier function for image offset task.
    Checks:
    1. Image was offset by exactly 150px right, 100px down
    2. Wrap-around behavior occurred correctly
    3. Dimensions remain unchanged
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
        "/home/ga/Desktop/offset_image.png",
        "/home/ga/Desktop/offset_image.jpg", 
        "/home/ga/Desktop/offset_image.jpeg",
        "/home/ga/Desktop/pattern_image_offset.jpg",
        "/home/ga/Desktop/pattern_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/pattern_image.jpg",
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
        
        # Verify offset using SSIM if available, else fallback method
        if ssim is not None:
            offset_correct, similarity_score, verification_method = verify_offset_with_ssim(
                original_image, result_image, 150, 100)
        else:
            offset_correct, similarity_score, verification_method = verify_offset_fallback(
                original_image, result_image, 150, 100)
        
        # Check for meaningful change
        change_analysis = check_meaningful_offset(original_image, result_image)
        
        # Check dimensions preserved
        dimensions_preserved = original_image.size == result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Verification method: {verification_method}")
        feedback_parts.append(f"Similarity score: {similarity_score:.3f}")
        feedback_parts.append(f"Offset correct (150px right, 100px down): {'✅' if offset_correct else '❌'}")
        feedback_parts.append(f"Dimensions preserved: {'✅' if dimensions_preserved else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 3
        
        if offset_correct:
            criteria_met += 1
        if dimensions_preserved:
            criteria_met += 1
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 67  # Need at least 2/3 criteria (67%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect image offset with wrap-around!")
        elif passed:
            feedback_parts.append("✅ Good image offset!")
        else:
            feedback_parts.append("❌ Image offset needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in image offset verification: {e}")
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
    result = check_image_offset([], {}, {})
    print(f"Test result: {result}")