#!/usr/bin/env python3
"""
Verifier for GIMP cartoon effect task.
Checks if cartoon filter was successfully applied with characteristic transformations.
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


def detect_edge_enhancement(original_img, result_img):
    """
    Detect increased edge strength characteristic of cartoon effect.
    Cartoon filter should enhance edges and create prominent outlines.
    """
    # Convert to grayscale for edge analysis
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Ensure same size for comparison
    if orig_gray.size != result_gray.size:
        result_gray = result_gray.resize(orig_gray.size)
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    try:
        # Use simple gradient-based edge detection (fallback if scipy not available)
        def simple_edge_detect(img_array):
            # Sobel-like operators
            gx = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
            gy = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]])
            
            edges_x = np.zeros_like(img_array, dtype=np.float32)
            edges_y = np.zeros_like(img_array, dtype=np.float32)
            
            for i in range(1, img_array.shape[0] - 1):
                for j in range(1, img_array.shape[1] - 1):
                    region = img_array[i-1:i+2, j-1:j+2].astype(np.float32)
                    edges_x[i, j] = np.sum(region * gx)
                    edges_y[i, j] = np.sum(region * gy)
            
            return np.sqrt(edges_x**2 + edges_y**2)
        
        try:
            # Try scipy if available
            from scipy.ndimage import sobel
            orig_edges = np.hypot(sobel(orig_array, axis=0), sobel(orig_array, axis=1))
            result_edges = np.hypot(sobel(result_array, axis=0), sobel(result_array, axis=1))
        except ImportError:
            # Use simple fallback
            orig_edges = simple_edge_detect(orig_array)
            result_edges = simple_edge_detect(result_array)
        
        # Count strong edge pixels (above threshold)
        edge_threshold = 0.1 * 255  # 10% of max intensity
        orig_strong_edges = np.sum(orig_edges > edge_threshold)
        result_strong_edges = np.sum(result_edges > edge_threshold)
        
        # Calculate edge increase ratio
        if orig_strong_edges > 0:
            edge_increase_ratio = result_strong_edges / orig_strong_edges
        else:
            edge_increase_ratio = 1.0
        
        # Cartoon effect should increase edge prominence
        enhanced = edge_increase_ratio >= 1.2  # At least 20% increase
        
        return {
            'enhanced': enhanced,
            'edge_increase_ratio': edge_increase_ratio,
            'orig_strong_edges': orig_strong_edges,
            'result_strong_edges': result_strong_edges
        }
        
    except Exception as e:
        logging.error(f"Edge detection failed: {e}")
        return {'enhanced': False, 'edge_increase_ratio': 1.0, 'orig_strong_edges': 0, 'result_strong_edges': 0}


def detect_color_simplification(original_img, result_img):
    """
    Detect posterization and color reduction characteristic of cartoon effect.
    """
    # Convert to RGB for color analysis
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Count unique colors (approximate, using quantized values)
    def count_approximate_colors(img_array, bins=32):
        """Count approximate unique colors by quantizing to reduce noise."""
        quantized = (img_array // (256 // bins)) * (256 // bins)
        unique_colors = np.unique(quantized.reshape(-1, 3), axis=0)
        return len(unique_colors)
    
    orig_colors = count_approximate_colors(orig_array)
    result_colors = count_approximate_colors(result_array)
    
    # Analyze histogram flattening/posterization
    orig_hist_variance = 0
    result_hist_variance = 0
    
    for channel in range(3):  # R, G, B
        orig_hist, _ = np.histogram(orig_array[:, :, channel], bins=50, range=(0, 256))
        result_hist, _ = np.histogram(result_array[:, :, channel], bins=50, range=(0, 256))
        
        orig_hist_variance += np.var(orig_hist)
        result_hist_variance += np.var(result_hist)
    
    # Color simplification indicators
    color_reduced = result_colors < orig_colors * 0.8  # At least 20% reduction
    histogram_changed = abs(result_hist_variance - orig_hist_variance) > orig_hist_variance * 0.1
    
    return {
        'simplified': color_reduced or histogram_changed,
        'orig_colors': orig_colors,
        'result_colors': result_colors,
        'color_reduction_ratio': result_colors / max(orig_colors, 1),
        'histogram_variance_change': result_hist_variance / max(orig_hist_variance, 1)
    }


def detect_detail_smoothing(original_img, result_img):
    """
    Detect reduction in fine detail characteristic of cartoon effect.
    """
    # Convert to grayscale for detail analysis
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
    
    # Compare local variance (detail level)
    orig_detail = np.std(orig_array)
    result_detail = np.std(result_array)
    
    # Compare texture using local standard deviation
    def local_std(img_array, window_size=5):
        """Calculate average local standard deviation."""
        h, w = img_array.shape
        local_stds = []
        
        for i in range(0, h - window_size, window_size):
            for j in range(0, w - window_size, window_size):
                window = img_array[i:i+window_size, j:j+window_size]
                local_stds.append(np.std(window))
        
        return np.mean(local_stds)
    
    orig_texture = local_std(orig_array)
    result_texture = local_std(result_array)
    
    # Cartoon effect should reduce detail/texture
    if orig_detail > 0:
        detail_ratio = result_detail / orig_detail
    else:
        detail_ratio = 1.0
    
    if orig_texture > 0:
        texture_ratio = result_texture / orig_texture
    else:
        texture_ratio = 1.0
    
    smoothed = detail_ratio < 0.9 or texture_ratio < 0.9  # At least 10% reduction
    
    return {
        'smoothed': smoothed,
        'detail_ratio': detail_ratio,
        'texture_ratio': texture_ratio,
        'orig_detail': orig_detail,
        'result_detail': result_detail
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Convert to arrays for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # Pixels with >30 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed significantly
    }


def check_cartoon_effect(traj, env_info, task_info):
    """
    Main verifier function for cartoon effect task.
    Checks:
    1. Enhanced edges (cartoon outlines)
    2. Simplified colors (posterization)
    3. Reduced detail (smoothing)
    4. Significant transformation occurred
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
        "/home/ga/Desktop/cartoon_image.jpg",
        "/home/ga/Desktop/cartoon_image.png",
        "/home/ga/Desktop/cartoon_image.jpeg",
        "/home/ga/Desktop/photo_original_cartoon.jpg",
        "/home/ga/Desktop/cartoon.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_original.jpg",
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
        
        # Analyze cartoon effect characteristics
        edge_analysis = detect_edge_enhancement(original_image, result_image)
        color_analysis = detect_color_simplification(original_image, result_image)
        detail_analysis = detect_detail_smoothing(original_image, result_image)
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge enhancement: {'✅' if edge_analysis['enhanced'] else '❌'}")
        feedback_parts.append(f"Edge increase ratio: {edge_analysis['edge_increase_ratio']:.2f}")
        feedback_parts.append(f"Color simplification: {'✅' if color_analysis['simplified'] else '❌'}")
        feedback_parts.append(f"Color reduction: {color_analysis['orig_colors']} → {color_analysis['result_colors']}")
        feedback_parts.append(f"Detail smoothing: {'✅' if detail_analysis['smoothed'] else '❌'}")
        feedback_parts.append(f"Detail ratio: {detail_analysis['detail_ratio']:.2f}")
        feedback_parts.append(f"Significant change: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Enhanced edges (cartoon outlines)
        if edge_analysis['enhanced']:
            criteria_met += 1
        
        # 2. Simplified colors (posterization effect)
        if color_analysis['simplified']:
            criteria_met += 1
        
        # 3. Reduced detail (smoothing effect)
        if detail_analysis['smoothed']:
            criteria_met += 1
        
        # 4. Significant transformation
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent cartoon transformation!")
        elif passed:
            feedback_parts.append("✅ Good cartoon effect applied!")
        else:
            feedback_parts.append("❌ Cartoon effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in cartoon effect verification: {e}")
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
    result = check_cartoon_effect([], {}, {})
    print(f"Test result: {result}")