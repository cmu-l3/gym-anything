#!/usr/bin/env python3
"""
Verifier for GIMP 90-degree rotation task.
Checks if image was rotated 90 degrees clockwise with proper dimension swapping.
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


def verify_rotation_90_clockwise(original_img, result_img):
    """
    Verify that result_img is a 90-degree clockwise rotation of original_img.
    Returns tuple: (ssim_match, dimensions_swapped, transformation_detected)
    """
    # Generate perfect reference rotation (90 degrees clockwise)
    # PIL's rotate() with positive angle rotates counter-clockwise, so use -90 for clockwise
    reference_rotated = original_img.rotate(-90, expand=True)
    
    # Check dimension swapping
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    ref_w, ref_h = reference_rotated.size
    
    dimensions_swapped = (result_w == orig_h and result_h == orig_w and 
                         result_w == ref_w and result_h == ref_h)
    
    logging.debug(f"Original dimensions: {orig_w}x{orig_h}")
    logging.debug(f"Result dimensions: {result_w}x{result_h}")
    logging.debug(f"Reference dimensions: {ref_w}x{ref_h}")
    logging.debug(f"Dimensions properly swapped: {dimensions_swapped}")
    
    # Check if image was actually modified
    transformation_detected = not (result_img.size == original_img.size and 
                                 np.array_equal(np.array(original_img), np.array(result_img)))
    
    # SSIM comparison with reference
    ssim_match = False
    ssim_score = 0.0
    
    if HAS_SSIM and result_img.size == reference_rotated.size:
        try:
            # Ensure both images are in RGB format
            if reference_rotated.mode != 'RGB':
                reference_rotated = reference_rotated.convert('RGB')
            if result_img.mode != 'RGB':
                result_img = result_img.convert('RGB')
            
            # Convert to arrays
            ref_array = np.array(reference_rotated)
            result_array = np.array(result_img)
            
            # Calculate SSIM
            min_dim = min(ref_array.shape[0], ref_array.shape[1])
            win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
            if win_size < 1:
                win_size = 1
            
            try:
                # Try newer SSIM API first
                ssim_score = ssim(ref_array, result_array, win_size=win_size, 
                                channel_axis=2, data_range=255)
            except TypeError:
                # Fall back to older API
                ssim_score = ssim(ref_array, result_array, win_size=win_size, 
                                multichannel=True, data_range=255)
            
            ssim_match = ssim_score >= 0.95
            logging.debug(f"SSIM score: {ssim_score:.4f}, Match: {ssim_match}")
            
        except Exception as e:
            logging.error(f"SSIM calculation failed: {e}")
            # Fallback to basic pixel comparison
            if result_img.size == reference_rotated.size:
                pixel_diff = np.mean(np.abs(np.array(reference_rotated).astype(float) - 
                                          np.array(result_img).astype(float)))
                ssim_match = pixel_diff < 10  # Very similar images
                logging.debug(f"Fallback pixel difference: {pixel_diff:.2f}")
    
    return ssim_match, dimensions_swapped, transformation_detected, ssim_score


def check_rotation_90(traj, env_info, task_info):
    """
    Main verifier function for 90-degree rotation task.
    Checks:
    1. Image was rotated 90 degrees clockwise (SSIM ≥ 0.95 with reference)
    2. Dimensions are properly swapped (width becomes height, height becomes width)
    3. Image was actually modified from original
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
        "/home/ga/Desktop/rotated_landscape.png",
        "/home/ga/Desktop/rotated_landscape.jpg", 
        "/home/ga/Desktop/rotated_landscape.jpeg",
        "/home/ga/Desktop/landscape_rotated.png",
        "/home/ga/Desktop/landscape_rotated.jpg",
        "/home/ga/Desktop/landscape_image_rotated.png"
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
        
        # Verify 90-degree clockwise rotation
        ssim_match, dimensions_swapped, transformation_detected, ssim_score = verify_rotation_90_clockwise(
            original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"SSIM score: {ssim_score:.4f}")
        feedback_parts.append(f"Perfect rotation match: {'✅' if ssim_match else '❌'}")
        feedback_parts.append(f"Dimensions swapped: {'✅' if dimensions_swapped else '❌'}")
        feedback_parts.append(f"Image transformed: {'✅' if transformation_detected else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 3
        
        if ssim_match:
            criteria_met += 1
        if dimensions_swapped:
            criteria_met += 1
        if transformation_detected:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 2/3 criteria, but preferably all 3
        
        # Additional check: if we have perfect SSIM and dimensions, that's a perfect score
        if ssim_match and dimensions_swapped:
            score = 100
            passed = True
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect 90-degree clockwise rotation!")
        elif passed:
            feedback_parts.append("✅ Good rotation!")
        else:
            feedback_parts.append("❌ Rotation not completed correctly")
            
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
    result = check_rotation_90([], {}, {})
    print(f"Test result: {result}")