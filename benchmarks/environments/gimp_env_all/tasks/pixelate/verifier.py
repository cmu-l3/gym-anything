#!/usr/bin/env python3
"""
Verifier for GIMP pixelate filter task.
Checks if pixelation was successfully applied using multi-metric analysis.
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


def analyze_color_reduction(original_img, result_img):
    """
    Analyze reduction in unique colors due to pixelation.
    Returns the percentage reduction in unique colors.
    """
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Count unique colors (combinations of R,G,B values)
    orig_colors = len(np.unique(orig_array.reshape(-1, 3), axis=0))
    result_colors = len(np.unique(result_array.reshape(-1, 3), axis=0))
    
    # Calculate reduction percentage
    if orig_colors > 0:
        reduction_pct = ((orig_colors - result_colors) / orig_colors) * 100
    else:
        reduction_pct = 0
    
    return {
        'original_colors': orig_colors,
        'result_colors': result_colors,
        'reduction_percentage': reduction_pct,
        'significant_reduction': reduction_pct >= 30  # At least 30% reduction
    }


def analyze_block_uniformity(result_img, window_size=5):
    """
    Analyze local variance to detect uniform pixel blocks characteristic of pixelation.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    height, width = result_array.shape[:2]
    
    # Calculate local variance in sliding windows
    try:
        from scipy.ndimage import uniform_filter
        
        # Calculate variance for each color channel
        total_variance = np.zeros((height, width))
        
        for channel in range(3):
            channel_data = result_array[:, :, channel].astype(np.float32)
            
            # Local mean and squared mean using uniform filter
            local_mean = uniform_filter(channel_data, size=window_size)
            local_sq_mean = uniform_filter(channel_data**2, size=window_size)
            
            # Local variance = E[X²] - E[X]²
            local_var = local_sq_mean - local_mean**2
            total_variance += local_var
        
        # Average variance across channels
        avg_variance = total_variance / 3
        
    except ImportError:
        # Fallback method without scipy
        logging.warning("scipy not available, using fallback variance calculation")
        
        # Simple grid-based variance calculation
        avg_variance = np.zeros((height, width))
        half_window = window_size // 2
        
        for y in range(half_window, height - half_window):
            for x in range(half_window, width - half_window):
                # Extract window
                window = result_array[y-half_window:y+half_window+1, 
                                   x-half_window:x+half_window+1]
                # Calculate variance across the window for all channels
                window_var = np.var(window.reshape(-1, 3), axis=0)
                avg_variance[y, x] = np.mean(window_var)
    
    # Count low-variance regions (uniform blocks)
    low_variance_threshold = 5  # Pixels with variance < 5 are considered uniform
    low_variance_pixels = np.sum(avg_variance < low_variance_threshold)
    total_pixels = height * width
    
    low_variance_ratio = low_variance_pixels / total_pixels if total_pixels > 0 else 0
    
    return {
        'low_variance_ratio': low_variance_ratio,
        'uniform_blocks_detected': low_variance_ratio >= 0.4,  # At least 40% uniform
        'avg_variance_overall': np.mean(avg_variance)
    }


def analyze_modification_level(original_img, result_img):
    """
    Analyze the level of modification between original and result images.
    """
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB arrays
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    pixel_diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(pixel_diff)
    
    # Count significantly changed pixels (change > 30 intensity units)
    significant_changes = np.sqrt(np.sum(pixel_diff ** 2, axis=2)) > 30
    change_percentage = np.sum(significant_changes) / significant_changes.size * 100
    
    return {
        'mean_pixel_difference': mean_diff,
        'change_percentage': change_percentage,
        'substantially_modified': mean_diff > 10,  # Mean difference > 10 units
        'significant_changes': change_percentage > 5  # At least 5% pixels significantly changed
    }


def detect_edge_pattern_changes(original_img, result_img):
    """
    Optional: Analyze changes in edge patterns (requires additional libraries).
    This is a simplified version that can work without opencv.
    """
    try:
        import cv2
        
        # Convert to grayscale for edge detection
        orig_gray = cv2.cvtColor(np.array(original_img.convert('RGB')), cv2.COLOR_RGB2GRAY)
        result_gray = cv2.cvtColor(np.array(result_img.convert('RGB')), cv2.COLOR_RGB2GRAY)
        
        # Apply Canny edge detection
        orig_edges = cv2.Canny(orig_gray, 50, 150)
        result_edges = cv2.Canny(result_gray, 50, 150)
        
        # Calculate edge density
        orig_edge_density = np.sum(orig_edges > 0) / orig_edges.size
        result_edge_density = np.sum(result_edges > 0) / result_edges.size
        
        edge_density_change = abs(result_edge_density - orig_edge_density) / orig_edge_density * 100
        
        return {
            'original_edge_density': orig_edge_density,
            'result_edge_density': result_edge_density,
            'edge_pattern_changed': edge_density_change > 20  # 20% change in edge density
        }
        
    except ImportError:
        # Fallback: simple gradient-based edge detection
        logging.debug("OpenCV not available, using simple gradient-based edge detection")
        
        orig_gray = np.array(original_img.convert('L'))
        result_gray = np.array(result_img.convert('L'))
        
        # Simple gradient calculation
        orig_grad_x = np.abs(np.diff(orig_gray, axis=1))
        orig_grad_y = np.abs(np.diff(orig_gray, axis=0))
        
        result_grad_x = np.abs(np.diff(result_gray, axis=1))
        result_grad_y = np.abs(np.diff(result_gray, axis=0))
        
        orig_edge_strength = np.mean(orig_grad_x) + np.mean(orig_grad_y)
        result_edge_strength = np.mean(result_grad_x) + np.mean(result_grad_y)
        
        edge_change = abs(result_edge_strength - orig_edge_strength) / orig_edge_strength * 100 if orig_edge_strength > 0 else 0
        
        return {
            'original_edge_strength': orig_edge_strength,
            'result_edge_strength': result_edge_strength,
            'edge_pattern_changed': edge_change > 20
        }


def check_pixelate_filter(traj, env_info, task_info):
    """
    Main verifier function for pixelate filter task.
    Checks:
    1. Color reduction (unique colors decreased significantly)
    2. Block uniformity (increased uniform regions)
    3. Substantial modification (image visibly changed)
    4. Edge pattern changes (optional)
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
        "/home/ga/Desktop/detailed_portrait_pixelated.jpg",
        "/home/ga/Desktop/portrait_pixelated.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/detailed_portrait.jpg",
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
        
        # Perform multi-metric analysis
        color_analysis = analyze_color_reduction(original_image, result_image)
        uniformity_analysis = analyze_block_uniformity(result_image)
        modification_analysis = analyze_modification_level(original_image, result_image)
        edge_analysis = detect_edge_pattern_changes(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original colors: {color_analysis['original_colors']}")
        feedback_parts.append(f"Result colors: {color_analysis['result_colors']}")
        feedback_parts.append(f"Color reduction: {color_analysis['reduction_percentage']:.1f}%")
        feedback_parts.append(f"Uniform blocks ratio: {uniformity_analysis['low_variance_ratio']:.2f}")
        feedback_parts.append(f"Mean pixel diff: {modification_analysis['mean_pixel_difference']:.1f}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant color reduction (at least 30%)
        if color_analysis['significant_reduction']:
            criteria_met += 1
        feedback_parts.append(f"Color reduction ≥30%: {'✅' if color_analysis['significant_reduction'] else '❌'}")
        
        # 2. Block uniformity (at least 40% of image shows uniform blocks)
        if uniformity_analysis['uniform_blocks_detected']:
            criteria_met += 1
        feedback_parts.append(f"Uniform blocks ≥40%: {'✅' if uniformity_analysis['uniform_blocks_detected'] else '❌'}")
        
        # 3. Substantial modification (mean pixel difference > 10)
        if modification_analysis['substantially_modified']:
            criteria_met += 1
        feedback_parts.append(f"Substantially modified: {'✅' if modification_analysis['substantially_modified'] else '❌'}")
        
        # 4. Edge pattern change (optional but included in scoring)
        if edge_analysis['edge_pattern_changed']:
            criteria_met += 1
        feedback_parts.append(f"Edge pattern changed: {'✅' if edge_analysis['edge_pattern_changed'] else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent pixelation effect applied!")
        elif passed:
            feedback_parts.append("✅ Good pixelation effect applied!")
        else:
            feedback_parts.append("❌ Pixelation effect needs improvement or wasn't applied")
            
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
    result = check_pixelate_filter([], {}, {})
    print(f"Test result: {result}")