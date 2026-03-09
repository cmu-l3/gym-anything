#!/usr/bin/env python3
"""
Verifier for GIMP pixelate effect task.
Checks if pixelate filter was applied to create blocky, grid-like patterns.
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


def detect_pixelation_by_edge_analysis(original_img, result_img):
    """
    Detect pixelation using edge analysis and pattern recognition.
    Pixelation creates regular grid patterns that can be detected.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for edge analysis
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    result_array = np.array(result_gray)
    
    # Edge detection using simple gradients (Sobel-like)
    try:
        from scipy import ndimage
        
        # Calculate gradients in x and y directions
        dx = ndimage.sobel(result_array, axis=1)  # Vertical edges
        dy = ndimage.sobel(result_array, axis=0)  # Horizontal edges
        
        # Analyze edge patterns for grid regularity
        height, width = result_array.shape
        
        # Sum edges along rows and columns to find regular patterns
        horizontal_edges = np.sum(np.abs(dy), axis=1)  # Sum across rows
        vertical_edges = np.sum(np.abs(dx), axis=0)    # Sum across columns
        
        # Detect regular peaks (indicating grid pattern)
        def find_regular_spacing(signal, min_spacing=5):
            """Find regular spacing in 1D signal indicating grid pattern."""
            if len(signal) < 10:
                return None, 0
            
            # Find peaks in the signal
            from scipy.signal import find_peaks
            
            # Use prominence to find significant peaks
            avg_signal = np.mean(signal)
            peaks, properties = find_peaks(signal, 
                                         distance=min_spacing, 
                                         prominence=avg_signal * 0.3)
            
            if len(peaks) < 3:
                return None, 0
            
            # Calculate spacings between consecutive peaks
            spacings = np.diff(peaks)
            
            # Check if spacings are regular (low standard deviation)
            if len(spacings) < 2:
                return None, 0
            
            mean_spacing = np.mean(spacings)
            std_spacing = np.std(spacings)
            regularity_score = std_spacing / (mean_spacing + 1e-6)
            
            # Good grid should have regularity score < 0.4
            if regularity_score < 0.4 and mean_spacing >= min_spacing:
                return mean_spacing, len(peaks)
            
            return None, 0
        
        # Analyze both horizontal and vertical edge patterns
        h_spacing, h_peaks = find_regular_spacing(horizontal_edges)
        v_spacing, v_peaks = find_regular_spacing(vertical_edges)
        
        # Estimate block size from grid spacing
        estimated_block_size = None
        if h_spacing and v_spacing:
            estimated_block_size = (h_spacing + v_spacing) / 2
        elif h_spacing:
            estimated_block_size = h_spacing
        elif v_spacing:
            estimated_block_size = v_spacing
        
        return {
            'grid_detected': estimated_block_size is not None,
            'estimated_block_size': estimated_block_size,
            'horizontal_peaks': h_peaks,
            'vertical_peaks': v_peaks,
            'h_spacing': h_spacing,
            'v_spacing': v_spacing
        }
        
    except ImportError:
        # Fallback: simple block detection without scipy
        logging.warning("SciPy not available, using simple block detection")
        return detect_pixelation_simple(result_array)


def detect_pixelation_simple(img_array):
    """Simple pixelation detection without advanced libraries."""
    height, width = img_array.shape
    
    # Look for blocky patterns by analyzing variance in small regions
    block_sizes = [8, 10, 12, 16, 20]  # Test different possible block sizes
    best_block_size = None
    best_score = 0
    
    for block_size in block_sizes:
        if block_size > min(height, width) // 4:
            continue
            
        # Count how many block-sized regions have low variance (pixelated)
        low_variance_blocks = 0
        total_blocks = 0
        
        for y in range(0, height - block_size, block_size // 2):
            for x in range(0, width - block_size, block_size // 2):
                block = img_array[y:y+block_size, x:x+block_size]
                variance = np.var(block)
                
                total_blocks += 1
                if variance < 100:  # Low variance indicates flat regions
                    low_variance_blocks += 1
        
        if total_blocks > 0:
            flat_ratio = low_variance_blocks / total_blocks
            if flat_ratio > 0.3 and flat_ratio > best_score:  # At least 30% flat blocks
                best_score = flat_ratio
                best_block_size = block_size
    
    return {
        'grid_detected': best_block_size is not None,
        'estimated_block_size': best_block_size,
        'flat_ratio': best_score,
        'horizontal_peaks': 0,
        'vertical_peaks': 0
    }


def analyze_detail_reduction(original_img, result_img):
    """Analyze how much detail was lost due to pixelation."""
    # Convert to grayscale arrays
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
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Calculate standard deviation (measure of detail/texture)
    orig_std = np.std(orig_array)
    result_std = np.std(result_array)
    
    # Calculate local variance to measure smoothness
    try:
        from scipy.ndimage import generic_filter
        
        # Calculate local variance using a 5x5 window
        orig_local_var = generic_filter(orig_array.astype(float), np.var, size=5)
        result_local_var = generic_filter(result_array.astype(float), np.var, size=5)
        
        orig_avg_local_var = np.mean(orig_local_var)
        result_avg_local_var = np.mean(result_local_var)
        
        # Pixelation should reduce local variance (make regions smoother)
        variance_reduction = 1 - (result_avg_local_var / (orig_avg_local_var + 1e-6))
        
    except ImportError:
        # Fallback without scipy
        variance_reduction = 1 - (result_std / (orig_std + 1e-6))
    
    detail_retention = result_std / (orig_std + 1e-6)
    
    return {
        'original_std': orig_std,
        'result_std': result_std,
        'detail_retention': detail_retention,
        'detail_reduction': 1 - detail_retention,
        'variance_reduction': variance_reduction
    }


def analyze_color_palette_reduction(original_img, result_img):
    """Analyze reduction in unique colors (pixelation typically reduces color palette)."""
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Get unique colors
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_colors = len(set(original_img.getdata()))
    result_colors = len(set(result_img.getdata()))
    
    color_reduction = 1 - (result_colors / max(orig_colors, 1))
    
    return {
        'original_colors': orig_colors,
        'result_colors': result_colors,
        'color_reduction': color_reduction
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size
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
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed
    }


def check_pixelate_effect(traj, env_info, task_info):
    """
    Main verifier function for pixelate effect task.
    Checks:
    1. Block pattern detected through edge analysis
    2. Sufficient pixelation (block size ≥8 pixels)
    3. Detail reduction occurred
    4. Color palette was reduced
    5. Image was meaningfully modified
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
        "/home/ga/Desktop/test_image_pixelated.jpg",
        "/home/ga/Desktop/test_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/test_image.jpg",
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
        
        # Analyze pixelation pattern
        pixelation_analysis = detect_pixelation_by_edge_analysis(original_image, result_image)
        
        # Analyze detail reduction
        detail_analysis = analyze_detail_reduction(original_image, result_image)
        
        # Analyze color palette reduction
        color_analysis = analyze_color_palette_reduction(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        
        if pixelation_analysis['estimated_block_size']:
            feedback_parts.append(f"Estimated block size: {pixelation_analysis['estimated_block_size']:.1f}px")
        
        feedback_parts.append(f"Detail reduction: {detail_analysis['detail_reduction']:.1%}")
        feedback_parts.append(f"Color reduction: {color_analysis['color_reduction']:.1%}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Block pattern detected
        grid_detected = pixelation_analysis['grid_detected']
        if grid_detected:
            criteria_met += 1
        feedback_parts.append(f"Block pattern detected: {'✅' if grid_detected else '❌'}")
        
        # 2. Sufficient pixelation (block size ≥8 pixels)
        sufficient_pixelation = (pixelation_analysis['estimated_block_size'] and 
                               pixelation_analysis['estimated_block_size'] >= 8)
        if sufficient_pixelation:
            criteria_met += 1
        feedback_parts.append(f"Sufficient pixelation (≥8px blocks): {'✅' if sufficient_pixelation else '❌'}")
        
        # 3. Significant detail reduction (≥30%)
        detail_reduced = detail_analysis['detail_reduction'] >= 0.3
        if detail_reduced:
            criteria_met += 1
        feedback_parts.append(f"Detail reduction (≥30%): {'✅' if detail_reduced else '❌'}")
        
        # 4. Color palette reduction (≥10%)
        colors_reduced = color_analysis['color_reduction'] >= 0.1
        if colors_reduced:
            criteria_met += 1
        feedback_parts.append(f"Color palette reduced (≥10%): {'✅' if colors_reduced else '❌'}")
        
        # 5. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (rounded up from 3.75)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent pixelation effect!")
        elif passed:
            feedback_parts.append("✅ Good pixelation effect!")
        else:
            feedback_parts.append("❌ Pixelation effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in pixelate effect verification: {e}")
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