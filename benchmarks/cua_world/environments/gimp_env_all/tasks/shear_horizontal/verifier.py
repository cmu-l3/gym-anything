#!/usr/bin/env python3
"""
Verifier for GIMP horizontal shear task.
Checks if horizontal shear transformation was correctly applied.
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


def generate_shear_reference(original_img, shear_x_pixels=50):
    """
    Generate a mathematically correct horizontal shear reference image.
    """
    try:
        from scipy import ndimage
        import cv2
        HAS_SCIPY = True
        HAS_CV2 = True
    except ImportError:
        HAS_SCIPY = False
        HAS_CV2 = False
    
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    
    img_array = np.array(original_img)
    h, w = img_array.shape[:2]
    
    if HAS_CV2:
        # Use OpenCV for high-quality shear transformation
        # Calculate shear factor: shear_x_pixels distributed across image height
        shear_factor = shear_x_pixels / h
        
        # Create affine transformation matrix for horizontal shear
        # Matrix format: [[1, shear_factor, 0], [0, 1, 0]]
        shear_matrix = np.float32([[1, shear_factor, 0], [0, 1, 0]])
        
        # Calculate new width to accommodate shear
        new_width = w + abs(shear_x_pixels)
        
        # Apply affine transformation
        sheared_array = cv2.warpAffine(img_array, shear_matrix, (new_width, h), 
                                     borderMode=cv2.BORDER_CONSTANT, 
                                     borderValue=(255, 255, 255))
        
        return Image.fromarray(sheared_array)
    
    elif HAS_SCIPY:
        # Use scipy for affine transformation
        shear_factor = shear_x_pixels / h
        
        # Create transformation matrix
        matrix = np.array([[1, -shear_factor], [0, 1]])  # Note: negative for proper direction
        
        # Apply transformation to each channel
        new_width = w + abs(shear_x_pixels)
        sheared_channels = []
        
        for channel in range(3):  # RGB channels
            channel_data = img_array[:, :, channel]
            sheared_channel = ndimage.affine_transform(
                channel_data,
                matrix,
                output_shape=(h, new_width),
                mode='constant',
                cval=255,
                offset=[0, shear_x_pixels/2 if shear_x_pixels > 0 else 0]
            )
            sheared_channels.append(sheared_channel)
        
        sheared_array = np.stack(sheared_channels, axis=2).astype(np.uint8)
        return Image.fromarray(sheared_array)
    
    else:
        # Fallback: Simple pixel shifting approximation
        logging.warning("Using fallback shear approximation - install scipy/opencv for better results")
        
        # Create larger canvas for sheared image
        new_width = w + abs(shear_x_pixels)
        sheared_img = Image.new('RGB', (new_width, h), (255, 255, 255))
        
        # Apply simple row-by-row shifting
        for y in range(h):
            # Calculate shift for this row
            shift = int((y / h) * shear_x_pixels)
            
            # Extract row from original
            row_data = original_img.crop((0, y, w, y + 1))
            
            # Paste shifted row onto sheared image
            sheared_img.paste(row_data, (shift, y))
        
        return sheared_img


def calculate_structural_similarity(img1, img2):
    """
    Calculate structural similarity between two images.
    Uses SSIM if available, otherwise uses MSE-based similarity.
    """
    try:
        from skimage.metrics import structural_similarity as ssim
        
        # Ensure images are same size
        if img1.size != img2.size:
            img2 = img2.resize(img1.size, Image.LANCZOS)
        
        # Convert to RGB arrays
        if img1.mode != 'RGB':
            img1 = img1.convert('RGB')
        if img2.mode != 'RGB':
            img2 = img2.convert('RGB')
        
        array1 = np.array(img1)
        array2 = np.array(img2)
        
        # Calculate SSIM
        similarity = ssim(array1, array2, multichannel=True, channel_axis=2)
        return similarity
        
    except ImportError:
        # Fallback: Simple MSE-based similarity
        logging.warning("SSIM not available, using MSE-based similarity")
        
        if img1.size != img2.size:
            img2 = img2.resize(img1.size, Image.LANCZOS)
        
        array1 = np.array(img1.convert('RGB')).astype(np.float32)
        array2 = np.array(img2.convert('RGB')).astype(np.float32)
        
        mse = np.mean((array1 - array2) ** 2)
        max_pixel_value = 255.0
        similarity = 1.0 - (mse / (max_pixel_value ** 2))
        
        return max(0, similarity)


def analyze_dimension_change(original_img, result_img):
    """
    Analyze if dimensions changed appropriately for horizontal shear.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # For horizontal shear, height should remain the same, width should increase
    height_preserved = orig_h == result_h
    width_increased = result_w > orig_w
    
    width_increase = result_w - orig_w
    
    return {
        'height_preserved': height_preserved,
        'width_increased': width_increased,
        'width_increase': width_increase,
        'appropriate_expansion': width_increased and 20 <= width_increase <= 100  # Reasonable range
    }


def check_meaningful_transformation(original_img, result_img):
    """
    Check if the result image is meaningfully different from the original.
    """
    # Resize result to match original for pixel comparison
    if original_img.size != result_img.size:
        result_comparison = result_img.resize(original_img.size, Image.LANCZOS)
    else:
        result_comparison = result_img
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_comparison.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_changes = np.sqrt(np.sum(diff ** 2, axis=2)) > 20  # Threshold for significant change
    change_percentage = np.mean(significant_changes) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_transformed': change_percentage > 10  # At least 10% of pixels changed
    }


def check_horizontal_shear(traj, env_info, task_info):
    """
    Main verifier function for horizontal shear task.
    Checks:
    1. Image dimensions changed appropriately (width increased, height preserved)
    2. Result matches expected shear transformation (SSIM comparison)
    3. Image was meaningfully transformed
    4. Quality maintained (no major corruption)
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
        "/home/ga/Desktop/sheared_image.jpg",
        "/home/ga/Desktop/sheared_image.png",
        "/home/ga/Desktop/sheared_image.jpeg",
        "/home/ga/Desktop/test_shear_sheared.jpg",
        "/home/ga/Desktop/transformed_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/test_shear.jpg",
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
        
        # Generate reference shear image
        reference_image = generate_shear_reference(original_image, shear_x_pixels=50)
        
        # Analyze dimension changes
        dimension_analysis = analyze_dimension_change(original_image, result_image)
        
        # Calculate similarity with reference
        similarity_score = calculate_structural_similarity(reference_image, result_image)
        
        # Check for meaningful transformation
        transformation_analysis = check_meaningful_transformation(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Width increased: {'✅' if dimension_analysis['width_increased'] else '❌'}")
        feedback_parts.append(f"Height preserved: {'✅' if dimension_analysis['height_preserved'] else '❌'}")
        feedback_parts.append(f"Width increase: {dimension_analysis['width_increase']}px")
        feedback_parts.append(f"Reference similarity: {similarity_score:.3f}")
        feedback_parts.append(f"Pixels changed: {transformation_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Appropriate dimension change
        if dimension_analysis['appropriate_expansion']:
            criteria_met += 1
        feedback_parts.append(f"Appropriate expansion: {'✅' if dimension_analysis['appropriate_expansion'] else '❌'}")
        
        # 2. Good similarity with reference (SSIM >= 0.85)
        reference_match = similarity_score >= 0.85
        if reference_match:
            criteria_met += 1
        feedback_parts.append(f"Matches shear reference: {'✅' if reference_match else '❌'}")
        
        # 3. Meaningfully transformed
        if transformation_analysis['meaningfully_transformed']:
            criteria_met += 1
        feedback_parts.append(f"Image transformed: {'✅' if transformation_analysis['meaningfully_transformed'] else '❌'}")
        
        # 4. Quality maintained (not completely corrupted)
        quality_maintained = similarity_score > 0.3  # Reasonable minimum
        if quality_maintained:
            criteria_met += 1
        feedback_parts.append(f"Quality maintained: {'✅' if quality_maintained else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect horizontal shear transformation!")
        elif passed:
            feedback_parts.append("✅ Good horizontal shear transformation!")
        else:
            feedback_parts.append("❌ Horizontal shear transformation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in horizontal shear verification: {e}")
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
    result = check_horizontal_shear([], {}, {})
    print(f"Test result: {result}")