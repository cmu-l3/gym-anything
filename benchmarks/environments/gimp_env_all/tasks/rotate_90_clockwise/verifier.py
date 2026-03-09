#!/usr/bin/env python3
"""
Verifier for GIMP 90-degree clockwise rotation task.
Checks if image was rotated exactly 90 degrees clockwise.
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


def check_dimension_swap(original_img, result_img, tolerance=2):
    """Check if image dimensions were properly swapped during 90-degree rotation."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # For 90-degree rotation, width and height should swap
    expected_w, expected_h = orig_h, orig_w
    
    width_ok = abs(result_w - expected_w) <= tolerance
    height_ok = abs(result_h - expected_h) <= tolerance
    
    return width_ok and height_ok, (result_w, result_h), (expected_w, expected_h)


def verify_90_degree_clockwise_rotation(original_img, result_img):
    """
    Verify if result is a 90-degree clockwise rotation of original.
    Uses mathematical rotation comparison with SSIM for robustness.
    """
    try:
        # Generate perfect reference rotation
        # PIL rotate uses counter-clockwise positive angles, so -90 = clockwise 90
        reference_rotated = original_img.rotate(-90, expand=True)
        
        # Check if result matches reference
        if HAS_SSIM:
            # Use SSIM for robust comparison
            if result_img.size != reference_rotated.size:
                logging.debug(f"Size mismatch: result {result_img.size} vs reference {reference_rotated.size}")
                return False, 0.0
            
            # Convert to RGB for consistent comparison
            if reference_rotated.mode != 'RGB':
                reference_rotated = reference_rotated.convert('RGB')
            if result_img.mode != 'RGB':
                result_img = result_img.convert('RGB')
            
            ref_array = np.array(reference_rotated)
            result_array = np.array(result_img)
            
            # Calculate SSIM
            min_dim = min(ref_array.shape[0], ref_array.shape[1])
            win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
            if win_size < 3:
                win_size = 3
            
            try:
                # Try newer SSIM API first
                similarity = ssim(ref_array, result_array, win_size=win_size, channel_axis=2)
            except TypeError:
                # Fallback to older API
                similarity = ssim(ref_array, result_array, win_size=win_size, multichannel=True)
            
            logging.debug(f"SSIM score: {similarity}")
            return similarity >= 0.95, similarity
            
        else:
            # Fallback: basic pixel comparison
            if result_img.size != reference_rotated.size:
                return False, 0.0
            
            # Convert to same mode for comparison
            if reference_rotated.mode != result_img.mode:
                reference_rotated = reference_rotated.convert(result_img.mode)
            
            ref_array = np.array(reference_rotated)
            result_array = np.array(result_img)
            
            # Calculate pixel difference
            diff = np.abs(ref_array.astype(np.float32) - result_array.astype(np.float32))
            mean_diff = np.mean(diff)
            
            # Consider rotation successful if mean difference is small
            threshold = 10.0  # Allow some compression/quality differences
            success = mean_diff < threshold
            similarity = max(0, 1.0 - mean_diff / 255.0)  # Normalize to 0-1
            
            logging.debug(f"Mean pixel difference: {mean_diff}, similarity: {similarity}")
            return success, similarity
            
    except Exception as e:
        logging.error(f"Error in rotation verification: {e}")
        return False, 0.0


def check_meaningful_rotation(original_img, result_img):
    """Check if the images are meaningfully different (rotation occurred)."""
    try:
        # Resize result to match original if needed for comparison
        if result_img.size != original_img.size:
            # For rotation, we expect size change, so this is actually expected
            # We'll compare structural differences instead of pixel-perfect match
            pass
        
        # Convert to same mode
        if original_img.mode != result_img.mode:
            result_img = result_img.convert(original_img.mode)
        
        # Check if images are identical (no rotation occurred)
        if original_img.size == result_img.size:
            orig_array = np.array(original_img)
            result_array = np.array(result_img)
            identical = np.array_equal(orig_array, result_array)
            return not identical  # Return True if NOT identical (rotation occurred)
        else:
            # Different sizes indicate transformation occurred
            return True
            
    except Exception as e:
        logging.error(f"Error checking meaningful rotation: {e}")
        return True  # Assume rotation occurred if we can't verify


def check_90_degree_rotation(traj, env_info, task_info):
    """
    Main verifier function for 90-degree clockwise rotation task.
    Checks:
    1. Image dimensions were swapped (W×H becomes H×W)
    2. Image content matches perfect 90-degree clockwise rotation
    3. Image was meaningfully changed from original
    4. Rotation direction is correct (clockwise, not counterclockwise)
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
        "/home/ga/Desktop/flower_rotated_90cw.jpg",
        "/home/ga/Desktop/flower_rotated_90cw.png",
        "/home/ga/Desktop/flower_rotated_90cw.jpeg",
        "/home/ga/Desktop/flower_rotated.jpg",
        "/home/ga/Desktop/rotated_flower.jpg",
        "/home/ga/Desktop/flower_image_rotated.jpg"
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
        
        # Check if dimensions were swapped correctly
        dims_swapped, actual_dims, expected_dims = check_dimension_swap(original_image, result_image)
        
        # Verify 90-degree clockwise rotation
        rotation_correct, similarity_score = verify_90_degree_clockwise_rotation(original_image, result_image)
        
        # Check if image was meaningfully changed
        image_rotated = check_meaningful_rotation(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Expected size: {expected_dims}")
        feedback_parts.append(f"Dimensions swapped: {'✅' if dims_swapped else '❌'}")
        feedback_parts.append(f"90° clockwise rotation: {'✅' if rotation_correct else '❌'}")
        feedback_parts.append(f"Similarity score: {similarity_score:.3f}")
        feedback_parts.append(f"Image modified: {'✅' if image_rotated else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dims_swapped:
            criteria_met += 1
        if rotation_correct:
            criteria_met += 1
        if image_rotated:
            criteria_met += 1
        if similarity_score >= 0.90:  # High similarity to reference rotation
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect 90-degree clockwise rotation!")
        elif passed:
            feedback_parts.append("✅ Good 90-degree clockwise rotation!")
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
    result = check_90_degree_rotation([], {}, {})
    print(f"Test result: {result}")