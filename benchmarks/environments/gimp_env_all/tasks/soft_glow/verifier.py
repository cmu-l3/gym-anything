#!/usr/bin/env python3
"""
Verifier for GIMP soft glow effect task.
Checks if soft glow filter was applied by analyzing brightness enhancement and blur.
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


def analyze_brightness_increase(original_img, result_img):
    """
    Measure brightness increase in highlight regions.
    Soft glow should increase brightness especially in highlight areas.
    """
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
    
    orig_array = np.array(orig_gray).astype(np.float32)
    result_array = np.array(result_gray).astype(np.float32)
    
    # Focus on highlight regions (top 10% brightness in original)
    highlight_threshold = np.percentile(orig_array, 90)
    highlight_mask = orig_array >= highlight_threshold
    
    if np.sum(highlight_mask) < 100:  # Safety check for sufficient highlight area
        logging.debug("Insufficient highlight area for analysis")
        return 0.0
    
    orig_highlights = orig_array[highlight_mask]
    result_highlights = result_array[highlight_mask]
    
    # Calculate percentage increase in highlight brightness
    orig_mean = np.mean(orig_highlights)
    result_mean = np.mean(result_highlights)
    
    if orig_mean > 0:
        brightness_increase = ((result_mean - orig_mean) / orig_mean) * 100
    else:
        brightness_increase = 0.0
    
    logging.debug(f"Brightness increase: {brightness_increase:.2f}%")
    return brightness_increase


def analyze_edge_softening(original_img, result_img):
    """
    Measure reduction in edge strength (blur detection).
    Soft glow should soften edges while preserving major features.
    """
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
    
    orig_array = np.array(orig_gray).astype(np.float32)
    result_array = np.array(result_gray).astype(np.float32)
    
    try:
        from scipy import ndimage
        
        # Sobel edge detection
        orig_edges_x = ndimage.sobel(orig_array, axis=0)
        orig_edges_y = ndimage.sobel(orig_array, axis=1)
        orig_edge_magnitude = np.sqrt(orig_edges_x**2 + orig_edges_y**2)
        
        result_edges_x = ndimage.sobel(result_array, axis=0)
        result_edges_y = ndimage.sobel(result_array, axis=1)
        result_edge_magnitude = np.sqrt(result_edges_x**2 + result_edges_y**2)
        
        # Calculate percentage reduction in edge strength
        orig_edge_strength = np.mean(orig_edge_magnitude)
        result_edge_strength = np.mean(result_edge_magnitude)
        
        if orig_edge_strength > 0:
            edge_reduction = ((orig_edge_strength - result_edge_strength) / orig_edge_strength) * 100
        else:
            edge_reduction = 0.0
        
        logging.debug(f"Edge reduction: {edge_reduction:.2f}%")
        return edge_reduction
        
    except ImportError:
        logging.warning("SciPy not available, using simple gradient analysis")
        
        # Fallback: simple gradient analysis
        orig_grad = np.gradient(orig_array)
        result_grad = np.gradient(result_array)
        
        orig_gradient_magnitude = np.sqrt(orig_grad[0]**2 + orig_grad[1]**2)
        result_gradient_magnitude = np.sqrt(result_grad[0]**2 + result_grad[1]**2)
        
        orig_grad_mean = np.mean(orig_gradient_magnitude)
        result_grad_mean = np.mean(result_gradient_magnitude)
        
        if orig_grad_mean > 0:
            edge_reduction = ((orig_grad_mean - result_grad_mean) / orig_grad_mean) * 100
        else:
            edge_reduction = 0.0
            
        logging.debug(f"Edge reduction (fallback): {edge_reduction:.2f}%")
        return edge_reduction


def detect_glow_halos(original_img, result_img):
    """
    Detect characteristic glow halos around bright regions.
    Soft glow should create luminous halos around highlights.
    """
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
    
    orig_array = np.array(orig_gray).astype(np.float32)
    result_array = np.array(result_gray).astype(np.float32)
    
    # Find bright regions in original (top 15% brightness)
    bright_threshold = np.percentile(orig_array, 85)
    bright_regions = orig_array >= bright_threshold
    
    if np.sum(bright_regions) < 50:  # Not enough bright regions
        logging.debug("Insufficient bright regions for halo detection")
        return False
    
    try:
        from scipy import ndimage
        
        # Dilate bright regions to create halo areas
        dilated_regions = ndimage.binary_dilation(bright_regions, iterations=5)
        halo_region = dilated_regions & ~bright_regions
        
        if np.sum(halo_region) < 100:
            logging.debug("Insufficient halo region for analysis")
            return False
        
        # Compare brightness in halo regions
        orig_halo_brightness = np.mean(orig_array[halo_region])
        result_halo_brightness = np.mean(result_array[halo_region])
        
        # Halo detected if surrounding areas are significantly brighter
        if orig_halo_brightness > 0:
            halo_increase = (result_halo_brightness - orig_halo_brightness) / orig_halo_brightness
            logging.debug(f"Halo brightness increase: {halo_increase:.3f}")
            return halo_increase > 0.05  # At least 5% brighter in halo region
        else:
            return False
            
    except ImportError:
        logging.warning("SciPy not available, using simple halo detection")
        
        # Fallback: simple expansion-based halo detection
        h, w = orig_array.shape
        halo_detected = False
        
        # Check a few sample points around bright areas
        for y in range(10, h-10, 20):
            for x in range(10, w-10, 20):
                if orig_array[y, x] >= bright_threshold:
                    # Check surrounding area
                    neighbors = result_array[y-5:y+6, x-5:x+6]
                    center = result_array[y, x]
                    
                    if neighbors.size > 0 and center > 0:
                        avg_neighbors = np.mean(neighbors)
                        if avg_neighbors > orig_array[y, x] * 1.1:  # 10% brighter
                            halo_detected = True
                            break
            if halo_detected:
                break
        
        logging.debug(f"Halo detected (fallback): {halo_detected}")
        return halo_detected


def check_image_modified(original_img, result_img):
    """Check if the images are meaningfully different."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array - result_array)
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    logging.debug(f"Mean pixel difference: {mean_diff:.2f}")
    logging.debug(f"Changed pixels: {change_percentage:.2f}%")
    
    return change_percentage > 3  # At least 3% of pixels changed significantly


def check_soft_glow(traj, env_info, task_info):
    """
    Main verifier function for soft glow effect task.
    Checks:
    1. Brightness increased in highlight regions (5-20%)
    2. Edges were softened (15-40% reduction)
    3. Glow halos are present around bright areas
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
        "/home/ga/Desktop/soft_glow_result.jpg",
        "/home/ga/Desktop/soft_glow_result.png",
        "/home/ga/Desktop/soft_glow_result.jpeg",
        "/home/ga/Desktop/portrait_softglow_edited.jpg",
        "/home/ga/Desktop/softglow_applied.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_softglow.jpg",
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
        
        # Analyze soft glow characteristics
        brightness_increase = analyze_brightness_increase(original_image, result_image)
        edge_reduction = analyze_edge_softening(original_image, result_image)
        glow_halos = detect_glow_halos(original_image, result_image)
        image_modified = check_image_modified(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Brightness increase: {brightness_increase:.1f}%")
        feedback_parts.append(f"Edge reduction: {edge_reduction:.1f}%")
        feedback_parts.append(f"Glow halos detected: {'✅' if glow_halos else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if image_modified else '❌'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Brightness increased in highlight regions (5-20%)
        brightness_good = 5.0 <= brightness_increase <= 20.0
        if brightness_good:
            criteria_met += 1
        feedback_parts.append(f"Brightness increased (5-20%): {'✅' if brightness_good else '❌'}")
        
        # 2. Edges were softened (15-40% reduction)
        edge_softening_good = 15.0 <= edge_reduction <= 40.0
        if edge_softening_good:
            criteria_met += 1
        feedback_parts.append(f"Edges softened (15-40%): {'✅' if edge_softening_good else '❌'}")
        
        # 3. Glow halos are present
        if glow_halos:
            criteria_met += 1
        
        # 4. Image was meaningfully modified
        if image_modified:
            criteria_met += 1
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent soft glow effect!")
        elif passed:
            feedback_parts.append("✅ Good soft glow effect!")
        else:
            feedback_parts.append("❌ Soft glow effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in soft glow verification: {e}")
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
    result = check_soft_glow([], {}, {})
    print(f"Test result: {result}")