#!/usr/bin/env python3
"""
Verifier for GIMP 90-degree clockwise rotation task.
Checks if image was rotated 90 degrees clockwise with proper dimension swap.
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
        logging.warning("SSIM not available, using basic comparison")


def generate_rotation_reference(original_img):
    """Generate perfect 90-degree clockwise rotation reference."""
    # 90° clockwise = -90° in PIL rotation (counterclockwise is positive)
    reference_rotated = original_img.rotate(-90, expand=True)
    return reference_rotated


def verify_dimension_swap(original_img, result_img):
    """Verify that dimensions were properly swapped during 90° rotation."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # After 90° clockwise rotation: original width → result height, original height → result width
    width_to_height = (orig_w == result_h)
    height_to_width = (orig_h == result_w)
    
    return width_to_height and height_to_width, (orig_w, orig_h), (result_w, result_h)


def compare_rotation_ssim(reference_img, result_img, threshold=0.95):
    """Compare two images using SSIM with high threshold for rotation accuracy."""
    if not HAS_SSIM:
        # Fallback to basic pixel comparison if SSIM unavailable
        return compare_rotation_basic(reference_img, result_img)
    
    # Ensure images are same size
    if reference_img.size != result_img.size:
        logging.debug(f"Size mismatch: reference {reference_img.size} vs result {result_img.size}")
        return False, 0.0
    
    # Convert to RGB if needed
    if reference_img.mode != 'RGB':
        reference_img = reference_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    ref_array = np.array(reference_img)
    result_array = np.array(result_img)
    
    # Check minimum size for SSIM
    min_dim = min(ref_array.shape[0], ref_array.shape[1])
    if min_dim < 7:
        logging.warning(f"Images too small for SSIM: {ref_array.shape}")
        return compare_rotation_basic(reference_img, result_img)
    
    try:
        # Calculate SSIM with appropriate window size
        win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
        
        # Try newer SSIM API first, then fallback to older
        try:
            similarity = ssim(ref_array, result_array, win_size=win_size, channel_axis=2)
        except TypeError:
            similarity = ssim(ref_array, result_array, win_size=win_size, multichannel=True)
        
        logging.debug(f"SSIM score: {similarity:.4f}")
        return similarity >= threshold, similarity
    
    except Exception as e:
        logging.error(f"SSIM calculation failed: {e}")
        return compare_rotation_basic(reference_img, result_img)


def compare_rotation_basic(reference_img, result_img):
    """Basic rotation comparison when SSIM is unavailable."""
    if reference_img.size != result_img.size:
        return False, 0.0
    
    # Convert to same format
    if reference_img.mode != result_img.mode:
        result_img = result_img.convert(reference_img.mode)
    
    # Calculate pixel differences
    ref_array = np.array(reference_img)
    result_array = np.array(result_img)
    
    # Calculate mean absolute difference
    diff = np.abs(ref_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Normalize to 0-1 scale (assuming 8-bit images)
    similarity = max(0, 1 - (mean_diff / 128.0))  # 128 is half of 255
    
    logging.debug(f"Basic similarity score: {similarity:.4f}")
    return similarity >= 0.9, similarity


def check_rotation_90cw(traj, env_info, task_info):
    """
    Main verifier function for 90-degree clockwise rotation task.
    Checks:
    1. Image was rotated 90 degrees clockwise
    2. Dimensions were properly swapped (width ↔ height)
    3. Rotation quality is high (SSIM ≥ 0.95)
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
        "/home/ga/Desktop/flower_rotated_90cw.jpg",
        "/home/ga/Desktop/flower_rotated_90cw.png", 
        "/home/ga/Desktop/flower_rotated_90cw.jpeg",
        "/home/ga/Desktop/flower_portrait_rotated.jpg",
        "/home/ga/Desktop/rotated_flower.jpg",
        "/home/ga/Desktop/flower_90cw.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_portrait.jpg",
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
        
        # Generate reference 90° clockwise rotation
        reference_rotated = generate_rotation_reference(original_image)
        
        # Check dimension swap
        dimensions_swapped, orig_dims, result_dims = verify_dimension_swap(original_image, result_image)
        
        # Compare with reference using SSIM
        rotation_correct, similarity_score = compare_rotation_ssim(reference_rotated, result_image)
        
        # Check if image was modified from original
        images_different = (original_image.size != result_image.size or 
                          not np.array_equal(np.array(original_image), 
                                           np.array(result_image.convert(original_image.mode))))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {orig_dims}")
        feedback_parts.append(f"Result size: {result_dims}")
        feedback_parts.append(f"Expected size after 90° CW: ({orig_dims[1]}, {orig_dims[0]})")
        feedback_parts.append(f"Dimensions swapped correctly: {'✅' if dimensions_swapped else '❌'}")
        feedback_parts.append(f"Rotation matches reference: {'✅' if rotation_correct else '❌'}")
        feedback_parts.append(f"Similarity score: {similarity_score:.3f}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimensions_swapped:
            criteria_met += 1
        if rotation_correct:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        # Quality criterion: good similarity score
        if similarity_score > 0.85:  # Slightly lower threshold for bonus points
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
    result = check_rotation_90cw([], {}, {})
    print(f"Test result: {result}")