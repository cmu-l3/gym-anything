#!/usr/bin/env python3
"""
Verifier for GIMP pixelate effect task.
Checks if image was successfully pixelated with visible mosaic effect.
"""

import logging
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np
import sys
import os

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def detect_pixelated_blocks(img_array, block_size=8):
    """
    Detect presence of uniform color blocks characteristic of pixelation.
    Uses grid-based analysis to find regions with low variance (uniform color).
    """
    if img_array.ndim == 3:
        # Convert to grayscale for analysis
        gray_array = np.mean(img_array, axis=2)
    else:
        gray_array = img_array
    
    height, width = gray_array.shape
    uniform_block_count = 0
    total_blocks = 0
    
    # Analyze image in small blocks
    for y in range(0, height - block_size, block_size):
        for x in range(0, width - block_size, block_size):
            block = gray_array[y:y+block_size, x:x+block_size]
            
            # Calculate standard deviation within block
            std_dev = np.std(block)
            
            # Low standard deviation indicates uniform color block (pixelated)
            if std_dev < 15:  # Threshold for "uniform"
                uniform_block_count += 1
            total_blocks += 1
    
    if total_blocks == 0:
        return False, 0.0
    
    uniformity_ratio = uniform_block_count / total_blocks
    return uniformity_ratio >= 0.40, uniformity_ratio  # At least 40% uniform blocks


def measure_detail_reduction(original_img, result_img):
    """
    Measure reduction in detail using edge detection and variance analysis.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Method 1: Edge detection comparison
    try:
        orig_edges = orig_gray.filter(ImageFilter.FIND_EDGES)
        result_edges = result_gray.filter(ImageFilter.FIND_EDGES)
        
        orig_edge_count = np.sum(np.array(orig_edges) > 30)
        result_edge_count = np.sum(np.array(result_edges) > 30)
        
        if orig_edge_count > 0:
            edge_reduction = (orig_edge_count - result_edge_count) / orig_edge_count
        else:
            edge_reduction = 0
    except Exception as e:
        logging.warning(f"Edge detection failed: {e}")
        edge_reduction = 0
    
    # Method 2: Local variance comparison
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Calculate local variance using a sliding window approach
    def local_variance(arr, window_size=5):
        from scipy.ndimage import uniform_filter
        try:
            # Use scipy if available
            mean = uniform_filter(arr.astype(np.float32), size=window_size)
            sqr_mean = uniform_filter((arr.astype(np.float32))**2, size=window_size)
            return sqr_mean - mean**2
        except ImportError:
            # Fallback: simple block-based variance
            h, w = arr.shape
            variance_map = np.zeros_like(arr, dtype=np.float32)
            for y in range(0, h-window_size, window_size//2):
                for x in range(0, w-window_size, window_size//2):
                    block = arr[y:y+window_size, x:x+window_size]
                    var = np.var(block.astype(np.float32))
                    variance_map[y:y+window_size, x:x+window_size] = var
            return variance_map
    
    orig_variance = local_variance(orig_array)
    result_variance = local_variance(result_array)
    
    orig_avg_variance = np.mean(orig_variance)
    result_avg_variance = np.mean(result_variance)
    
    if orig_avg_variance > 0:
        variance_reduction = (orig_avg_variance - result_avg_variance) / orig_avg_variance
    else:
        variance_reduction = 0
    
    # Combine both metrics
    significant_reduction = edge_reduction >= 0.5 or variance_reduction >= 0.3
    
    return {
        'edge_reduction': edge_reduction,
        'variance_reduction': variance_reduction,
        'significant_reduction': significant_reduction,
        'orig_edge_count': orig_edge_count if 'orig_edge_count' in locals() else 0,
        'result_edge_count': result_edge_count if 'result_edge_count' in locals() else 0
    }


def detect_low_variance_regions(img_array, threshold=20):
    """
    Detect regions with low variance that indicate pixelated blocks.
    """
    if img_array.ndim == 3:
        gray_array = np.mean(img_array, axis=2)
    else:
        gray_array = img_array
    
    height, width = gray_array.shape
    block_size = 16  # Check 16x16 blocks
    low_variance_count = 0
    total_regions = 0
    
    for y in range(0, height - block_size, block_size // 2):
        for x in range(0, width - block_size, block_size // 2):
            block = gray_array[y:y+block_size, x:x+block_size]
            variance = np.var(block)
            
            if variance < threshold:  # Low variance indicates uniform region
                low_variance_count += 1
            total_regions += 1
    
    if total_regions == 0:
        return False, 0.0
    
    low_variance_ratio = low_variance_count / total_regions
    return low_variance_ratio >= 0.25, low_variance_ratio  # At least 25% low-variance regions


def check_pixelate_effect(traj, env_info, task_info):
    """
    Main verifier function for pixelate effect task.
    Checks:
    1. Image contains uniform blocks characteristic of pixelation
    2. Significant detail reduction compared to original
    3. Low variance regions indicating mosaic effect
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
        "/home/ga/Desktop/pixelated_image.jpg",
        "/home/ga/Desktop/pixelated_image.png",
        "/home/ga/Desktop/pixelated_image.jpeg",
        "/home/ga/Desktop/detailed_image_pixelated.jpg",
        "/home/ga/Desktop/mosaic_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/detailed_image.jpg",
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
        
        # Convert to arrays for analysis
        orig_array = np.array(original_image)
        result_array = np.array(result_image.convert(original_image.mode))
        
        # Check 1: Detect uniform blocks characteristic of pixelation
        blocks_detected, uniformity_ratio = detect_pixelated_blocks(result_array)
        
        # Check 2: Measure detail reduction
        detail_analysis = measure_detail_reduction(original_image, result_image)
        
        # Check 3: Detect low variance regions (pixelated areas)
        low_var_detected, low_var_ratio = detect_low_variance_regions(result_array)
        
        # Check 4: Verify image was modified
        images_different = not np.array_equal(orig_array, result_array)
        if orig_array.shape != result_array.shape:
            images_different = True
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Uniform blocks detected: {'✅' if blocks_detected else '❌'} ({uniformity_ratio:.2f})")
        feedback_parts.append(f"Significant detail reduction: {'✅' if detail_analysis['significant_reduction'] else '❌'}")
        feedback_parts.append(f"Edge reduction: {detail_analysis['edge_reduction']:.2f}")
        feedback_parts.append(f"Variance reduction: {detail_analysis['variance_reduction']:.2f}")
        feedback_parts.append(f"Low variance regions: {'✅' if low_var_detected else '❌'} ({low_var_ratio:.2f})")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if blocks_detected:
            criteria_met += 1
        if detail_analysis['significant_reduction']:
            criteria_met += 1
        if low_var_detected:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect pixelate effect!")
        elif passed:
            feedback_parts.append("✅ Good pixelate effect applied!")
        else:
            feedback_parts.append("❌ Pixelate effect not detected or insufficient")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in pixelate verification: {e}")
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
    result = check_pixelate_effect([], {}, {})
    print(f"Test result: {result}")