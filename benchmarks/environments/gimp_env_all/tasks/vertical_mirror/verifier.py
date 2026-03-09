#!/usr/bin/env python3
"""
Verifier for GIMP vertical mirror task.
Checks if image was vertically flipped (top-to-bottom mirror).
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
    HAS_SSIM = True
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
        HAS_SSIM = True
    except ImportError:
        HAS_SSIM = False
        logging.warning("SSIM not available, using basic pixel comparison")


def calculate_ssim(img1, img2):
    """Calculate SSIM between two images with proper error handling."""
    if not HAS_SSIM:
        # Fallback to simple pixel comparison
        if img1.size != img2.size:
            return 0.0
        
        array1 = np.array(img1.convert('RGB'))
        array2 = np.array(img2.convert('RGB'))
        
        # Calculate mean squared error
        mse = np.mean((array1 - array2) ** 2)
        max_pixel_value = 255.0
        
        # Convert MSE to a similarity score (inverted and normalized)
        if mse == 0:
            return 1.0
        else:
            psnr = 20 * np.log10(max_pixel_value / np.sqrt(mse))
            # Normalize PSNR to 0-1 range (assuming good PSNR > 30dB)
            return min(psnr / 50.0, 1.0)
    
    # Ensure images are the same size
    if img1.size != img2.size:
        img2 = img2.resize(img1.size)
    
    # Convert to RGB for consistency
    if img1.mode != 'RGB':
        img1 = img1.convert('RGB')
    if img2.mode != 'RGB':
        img2 = img2.convert('RGB')
    
    array1 = np.array(img1)
    array2 = np.array(img2)
    
    # Determine appropriate window size
    min_dim = min(array1.shape[0], array1.shape[1])
    if min_dim < 7:
        win_size = min_dim if min_dim % 2 == 1 else min_dim - 1
        if win_size < 1:
            return 0.0
    else:
        win_size = 7
    
    try:
        # Try newer SSIM API first
        similarity = ssim(array1, array2, win_size=win_size, channel_axis=2)
    except TypeError:
        # Fall back to older API
        try:
            similarity = ssim(array1, array2, win_size=win_size, multichannel=True)
        except Exception as e:
            logging.error(f"SSIM calculation failed: {e}")
            return 0.0
    
    return similarity


def verify_vertical_flip(original_img, result_img):
    """
    Verify that result_img is a vertical flip of original_img.
    Returns similarity score and verification details.
    """
    # Generate perfect vertical flip reference using PIL
    reference_flip = original_img.transpose(Image.FLIP_TOP_BOTTOM)
    
    # Calculate similarity between result and reference flip
    flip_similarity = calculate_ssim(reference_flip, result_img)
    
    # Also check that it's different from the original (not unchanged)
    original_similarity = calculate_ssim(original_img, result_img)
    
    # Check dimensions are preserved
    dimensions_match = original_img.size == result_img.size
    
    return {
        'flip_similarity': flip_similarity,
        'original_similarity': original_similarity,
        'dimensions_match': dimensions_match,
        'is_properly_flipped': flip_similarity >= 0.95,
        'is_different_from_original': original_similarity < 0.9,
        'dimensions_preserved': dimensions_match
    }


def check_vertical_mirror(traj, env_info, task_info):
    """
    Main verifier function for vertical mirror task.
    Checks:
    1. Image was vertically flipped (top-to-bottom)
    2. Result matches perfect vertical flip with high SSIM
    3. Image dimensions are preserved
    4. Image was actually modified from original
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
        "/home/ga/Desktop/flower_vertical_mirror.png",
        "/home/ga/Desktop/flower_vertical_mirror.jpg", 
        "/home/ga/Desktop/flower_vertical_mirror.jpeg",
        "/home/ga/Desktop/vertical_mirror.png",
        "/home/ga/Desktop/flower_image_vertical.png",
        "/home/ga/Desktop/flower_flipped.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_image.jpg",
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
        
        # Verify vertical flip
        verification = verify_vertical_flip(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Vertical flip SSIM: {verification['flip_similarity']:.3f}")
        feedback_parts.append(f"Original SSIM: {verification['original_similarity']:.3f}")
        feedback_parts.append(f"Perfect vertical mirror: {'✅' if verification['is_properly_flipped'] else '❌'}")
        feedback_parts.append(f"Correctly axis (vertical): {'✅' if verification['is_properly_flipped'] else '❌'}")
        feedback_parts.append(f"Dimensions preserved: {'✅' if verification['dimensions_preserved'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if verification['is_different_from_original'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if verification['is_properly_flipped']:
            criteria_met += 1
        if verification['dimensions_preserved']:
            criteria_met += 1
        if verification['is_different_from_original']:
            criteria_met += 1
        
        # Bonus criterion: very high quality flip
        if verification['flip_similarity'] >= 0.98:
            criteria_met += 1
        elif verification['flip_similarity'] >= 0.95:
            criteria_met += 0.5  # Partial credit for good but not perfect flip
        
        # Score based on criteria met (adjusted for partial credit)
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria (or equivalent with partial credit)
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect vertical mirror!")
        elif passed:
            feedback_parts.append("✅ Good vertical mirror!")
        else:
            feedback_parts.append("❌ Vertical mirror needs improvement")
            
            # Additional diagnostic feedback for failure cases
            if verification['flip_similarity'] < 0.5:
                if verification['original_similarity'] > 0.9:
                    feedback_parts.append("⚠️ Image appears unchanged")
                else:
                    # Check if it might be horizontal flip instead
                    horizontal_flip = original_image.transpose(Image.FLIP_LEFT_RIGHT)
                    horizontal_similarity = calculate_ssim(horizontal_flip, result_image)
                    if horizontal_similarity > 0.8:
                        feedback_parts.append("⚠️ Appears to be horizontal flip instead of vertical")
                    else:
                        feedback_parts.append("⚠️ Unknown transformation applied")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in vertical mirror verification: {e}")
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
    result = check_vertical_mirror([], {}, {})
    print(f"Test result: {result}")