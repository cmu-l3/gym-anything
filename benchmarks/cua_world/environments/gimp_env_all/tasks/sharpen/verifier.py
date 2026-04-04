#!/usr/bin/env python3
"""
Verifier for GIMP sharpen filter task.
Checks if the image was successfully sharpened using Laplacian variance and edge detection metrics.
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

# Check for optional computer vision libraries
try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logging.warning("OpenCV not available, using PIL-based edge detection")

try:
    from scipy import ndimage
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False
    logging.warning("SciPy not available, using basic convolution")


def calculate_laplacian_variance(image):
    """
    Calculate image sharpness using Laplacian variance method.
    This is the standard metric for measuring image sharpness in computer vision.
    """
    # Convert to grayscale if needed
    if image.mode != 'L':
        gray_img = image.convert('L')
    else:
        gray_img = image
    
    # Convert to numpy array
    img_array = np.array(gray_img, dtype=np.float64)
    
    if HAS_CV2:
        # Use OpenCV Laplacian (more accurate)
        laplacian = cv2.Laplacian(img_array.astype(np.uint8), cv2.CV_64F)
        variance = laplacian.var()
    elif HAS_SCIPY:
        # Use SciPy with Laplacian kernel
        laplacian_kernel = np.array([[0, 1, 0], [1, -4, 1], [0, 1, 0]])
        laplacian = ndimage.convolve(img_array, laplacian_kernel)
        variance = laplacian.var()
    else:
        # Fallback: manual Laplacian convolution
        h, w = img_array.shape
        laplacian = np.zeros_like(img_array)
        
        # Apply Laplacian kernel manually (excluding borders)
        for i in range(1, h-1):
            for j in range(1, w-1):
                laplacian[i,j] = (img_array[i+1,j] + img_array[i-1,j] + 
                                img_array[i,j+1] + img_array[i,j-1] - 4*img_array[i,j])
        
        variance = laplacian.var()
    
    return variance


def calculate_edge_strength(image):
    """
    Calculate average edge strength using Sobel operator.
    Provides complementary measurement to Laplacian variance.
    """
    # Convert to grayscale if needed
    if image.mode != 'L':
        gray_img = image.convert('L')
    else:
        gray_img = image
    
    img_array = np.array(gray_img, dtype=np.float64)
    
    if HAS_CV2:
        # Use OpenCV Sobel operators
        sobelx = cv2.Sobel(img_array.astype(np.uint8), cv2.CV_64F, 1, 0, ksize=3)
        sobely = cv2.Sobel(img_array.astype(np.uint8), cv2.CV_64F, 0, 1, ksize=3)
        edge_magnitude = np.sqrt(sobelx**2 + sobely**2)
        return edge_magnitude.mean()
    elif HAS_SCIPY:
        # Use SciPy with Sobel kernels
        sobel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
        sobel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]])
        
        edge_x = ndimage.convolve(img_array, sobel_x)
        edge_y = ndimage.convolve(img_array, sobel_y)
        edge_magnitude = np.sqrt(edge_x**2 + edge_y**2)
        return edge_magnitude.mean()
    else:
        # Fallback: simple gradient calculation
        h, w = img_array.shape
        grad_x = np.zeros_like(img_array)
        grad_y = np.zeros_like(img_array)
        
        # Calculate gradients (excluding borders)
        grad_x[:, 1:-1] = img_array[:, 2:] - img_array[:, :-2]
        grad_y[1:-1, :] = img_array[2:, :] - img_array[:-2, :]
        
        edge_magnitude = np.sqrt(grad_x**2 + grad_y**2)
        return edge_magnitude.mean()


def analyze_sharpening_quality(original_img, result_img):
    """
    Comprehensive analysis of sharpening quality.
    Returns metrics and quality assessments.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Calculate sharpness metrics
    orig_sharpness = calculate_laplacian_variance(original_img)
    result_sharpness = calculate_laplacian_variance(result_img)
    
    orig_edges = calculate_edge_strength(original_img)
    result_edges = calculate_edge_strength(result_img)
    
    # Calculate improvements
    sharpness_improvement = ((result_sharpness - orig_sharpness) / max(orig_sharpness, 1)) * 100
    edge_improvement = ((result_edges - orig_edges) / max(orig_edges, 1)) * 100
    
    # Check for over-sharpening (excessive improvement might indicate artifacts)
    over_sharpened = sharpness_improvement > 200  # More than 200% increase might be artifacts
    
    # Check for meaningful change
    images_different = not np.array_equal(np.array(original_img.convert('RGB')), 
                                        np.array(result_img.convert('RGB')))
    
    return {
        'original_sharpness': orig_sharpness,
        'result_sharpness': result_sharpness,
        'sharpness_improvement': sharpness_improvement,
        'original_edges': orig_edges,
        'result_edges': result_edges,
        'edge_improvement': edge_improvement,
        'over_sharpened': over_sharpened,
        'images_different': images_different
    }


def check_sharpen_filter(traj, env_info, task_info):
    """
    Main verifier function for sharpen filter task.
    Checks:
    1. Image sharpness was significantly increased (Laplacian variance method)
    2. Edge strength was enhanced (Sobel edge detection)
    3. No excessive over-sharpening artifacts
    4. Image was actually modified
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
        "/home/ga/Desktop/sharpened_image.jpg",
        "/home/ga/Desktop/sharpened_image.png", 
        "/home/ga/Desktop/sharpened_image.jpeg",
        "/home/ga/Desktop/photo_to_sharpen_sharpened.jpg",
        "/home/ga/Desktop/photo_sharpened.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_to_sharpen.jpg",
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
        
        # Analyze sharpening quality
        analysis = analyze_sharpening_quality(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Sharpness improvement: {analysis['sharpness_improvement']:.1f}%")
        feedback_parts.append(f"Edge improvement: {analysis['edge_improvement']:.1f}%")
        feedback_parts.append(f"Over-sharpened: {'⚠️' if analysis['over_sharpened'] else '✅'}")
        feedback_parts.append(f"Image modified: {'✅' if analysis['images_different'] else '❌'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Meaningful sharpness increase (at least 20% Laplacian variance improvement)
        sharpness_good = analysis['sharpness_improvement'] >= 20.0
        if sharpness_good:
            criteria_met += 1
        feedback_parts.append(f"Sufficient sharpening: {'✅' if sharpness_good else '❌'}")
        
        # 2. Edge strength improved
        edges_improved = analysis['edge_improvement'] >= 10.0
        if edges_improved:
            criteria_met += 1
        feedback_parts.append(f"Edge strength improved: {'✅' if edges_improved else '❌'}")
        
        # 3. Not over-sharpened (no excessive artifacts)
        quality_maintained = not analysis['over_sharpened']
        if quality_maintained:
            criteria_met += 1
        feedback_parts.append(f"Quality maintained: {'✅' if quality_maintained else '❌'}")
        
        # 4. Image was actually modified
        if analysis['images_different']:
            criteria_met += 1
        
        # Calculate score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent sharpening filter application!")
        elif passed:
            feedback_parts.append("✅ Good sharpening filter applied!")
        else:
            feedback_parts.append("❌ Sharpening filter needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in sharpen filter verification: {e}")
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
    result = check_sharpen_filter([], {}, {})
    print(f"Test result: {result}")