#!/usr/bin/env python3
"""
Verifier for GIMP rotate 180° task.
Checks if image was rotated by exactly 180 degrees (upside-down).
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


def structure_check_by_ssim(img1, img2, threshold=0.95):
    """
    Check if two images are approximately the same using SSIM.
    Returns True if similarity is above threshold.
    """
    try:
        from skimage.metrics import structural_similarity as ssim
    except ImportError:
        try:
            # Fallback for older versions
            from skimage.measure import compare_ssim as ssim
        except ImportError:
            logging.warning("SSIM not available, using basic pixel comparison")
            return basic_image_comparison(img1, img2, threshold=0.98)
    
    # Ensure minimum size for SSIM computation
    min_size = 7
    if img1.width < min_size or img1.height < min_size or \
       img2.width < min_size or img2.height < min_size:
        logging.warning(f"Image too small for SSIM: {img1.size} vs {img2.size}")
        return basic_image_comparison(img1, img2, threshold=0.98)
    
    # Convert to RGB if needed
    if img1.mode != 'RGB':
        img1 = img1.convert('RGB')
    if img2.mode != 'RGB':
        img2 = img2.convert('RGB')
    
    # Check sizes match
    if img1.size != img2.size:
        logging.debug(f"Images have different sizes: {img1.size} vs {img2.size}")
        return False

    array1 = np.array(img1)
    array2 = np.array(img2)
    
    # Double check shapes match
    if array1.shape != array2.shape:
        logging.debug(f"Images have different shapes: {array1.shape} vs {array2.shape}")
        return False

    # Determine appropriate window size
    min_dim = min(array1.shape[0], array1.shape[1])
    if min_dim < 7:
        win_size = min_dim if min_dim % 2 == 1 else min_dim - 1
        if win_size < 1:
            logging.debug("Image too small for SSIM computation")
            return basic_image_comparison(img1, img2, threshold=0.98)
    else:
        win_size = 7

    try:
        # Try newer SSIM API first, fall back to older API
        try:
            similarity = ssim(array1, array2, win_size=win_size, channel_axis=2, data_range=255)
        except TypeError:
            similarity = ssim(array1, array2, win_size=win_size, multichannel=True, data_range=255)
        
        logging.debug(f"SSIM similarity: {similarity:.4f} (threshold: {threshold})")
        return similarity >= threshold
        
    except Exception as e:
        logging.error(f"SSIM computation failed: {e}")
        return basic_image_comparison(img1, img2, threshold=0.98)


def basic_image_comparison(img1, img2, threshold=0.98):
    """
    Fallback image comparison using pixel-wise differences.
    """
    if img1.size != img2.size:
        return False
    
    if img1.mode != img2.mode:
        img2 = img2.convert(img1.mode)
    
    array1 = np.array(img1).astype(np.float32)
    array2 = np.array(img2).astype(np.float32)
    
    # Calculate normalized cross-correlation
    diff = np.mean(np.abs(array1 - array2)) / 255.0
    similarity = 1.0 - diff
    
    logging.debug(f"Basic similarity: {similarity:.4f} (threshold: {threshold})")
    return similarity >= threshold


def check_image_changed(original_img, result_img):
    """
    Verify that the result image is actually different from the original.
    This prevents false positives where no rotation occurred.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    # Calculate mean absolute difference
    mean_diff = np.mean(np.abs(orig_array - result_array))
    
    # Images should be significantly different (threshold: >10.0 mean pixel difference)
    changed = mean_diff > 10.0
    
    logging.debug(f"Image change detected: mean_diff={mean_diff:.2f}, changed={changed}")
    return changed


def check_rotate_180(traj, env_info, task_info):
    """
    Main verifier function for rotate 180° task.
    Checks:
    1. Image was rotated by exactly 180 degrees
    2. Dimensions remain the same
    3. Image was actually modified (not left unchanged)
    4. Quality is preserved (no significant degradation)
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
        "/home/ga/Desktop/rotated_180.jpg",
        "/home/ga/Desktop/rotated_180.png", 
        "/home/ga/Desktop/rotated_180.jpeg",
        "/home/ga/Desktop/photo_original_rotated.jpg",
        "/home/ga/Desktop/photo_180.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_original.jpg",
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
        
        # Generate perfect 180° rotation reference using PIL
        reference_rotation = original_image.transpose(Image.Transpose.ROTATE_180)
        
        # Check if result matches the perfect 180° rotation
        rotation_correct = structure_check_by_ssim(reference_rotation, result_image, threshold=0.95)
        
        # Check dimensions preserved
        dimensions_preserved = original_image.size == result_image.size
        
        # Check that image was actually modified
        image_modified = check_image_changed(original_image, result_image)
        
        # Prepare feedback
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Perfect 180° rotation: {'✅' if rotation_correct else '❌'}")
        feedback_parts.append(f"Dimensions preserved: {'✅' if dimensions_preserved else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if image_modified else '❌'}")
        
        # Calculate success based on criteria
        criteria_met = 0
        total_criteria = 3
        
        if rotation_correct:
            criteria_met += 1
        if dimensions_preserved:
            criteria_met += 1 
        if image_modified:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/3 criteria for this simple task
        
        if passed and score == 100:
            feedback_parts.append("🎉 Perfect 180° rotation!")
        elif passed:
            feedback_parts.append("✅ Good 180° rotation!")
        else:
            feedback_parts.append("❌ 180° rotation not completed correctly")
            if not rotation_correct:
                feedback_parts.append("• Image was not rotated 180° or rotation is imprecise")
            if not dimensions_preserved:
                feedback_parts.append("• Image dimensions changed during rotation")
            if not image_modified:
                feedback_parts.append("• Image appears unchanged from original")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rotate 180° verification: {e}")
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
    result = check_rotate_180([], {}, {})
    print(f"Test result: {result}")