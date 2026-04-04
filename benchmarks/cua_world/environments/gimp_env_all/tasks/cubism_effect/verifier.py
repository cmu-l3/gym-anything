#!/usr/bin/env python3
"""
Verifier for GIMP cubism effect task.
Checks if cubism artistic filter was successfully applied to the image.
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


def analyze_edge_density(image):
    """
    Calculate edge density using Sobel edge detection.
    Cubism creates many geometric edges, so edge density should increase significantly.
    """
    # Convert to grayscale for edge detection
    if image.mode != 'L':
        gray_img = image.convert('L')
    else:
        gray_img = image
    
    img_array = np.array(gray_img).astype(np.float64)
    
    # Simple Sobel edge detection (fallback if scipy not available)
    try:
        from scipy import ndimage
        # Apply Sobel edge detection
        sobel_x = ndimage.sobel(img_array, axis=1)
        sobel_y = ndimage.sobel(img_array, axis=0)
        edge_magnitude = np.hypot(sobel_x, sobel_y)
    except ImportError:
        # Fallback: simple gradient calculation
        logging.debug("SciPy not available, using simple gradient")
        grad_x = np.gradient(img_array, axis=1)
        grad_y = np.gradient(img_array, axis=0)
        edge_magnitude = np.hypot(grad_x, grad_y)
    
    # Calculate edge density (percentage of pixels with significant edges)
    edge_threshold = np.percentile(edge_magnitude, 85)  # Top 15% of edge magnitudes
    strong_edges = edge_magnitude > edge_threshold
    edge_density = np.sum(strong_edges) / strong_edges.size
    
    return {
        'edge_density': edge_density,
        'mean_edge_magnitude': np.mean(edge_magnitude),
        'max_edge_magnitude': np.max(edge_magnitude),
        'edge_pixels': np.sum(strong_edges)
    }


def analyze_texture_complexity(image):
    """
    Analyze texture complexity using local variance.
    Cubism creates fragmented regions with varied textures.
    """
    if image.mode != 'L':
        gray_img = image.convert('L')
    else:
        gray_img = image
    
    img_array = np.array(gray_img).astype(np.float64)
    
    # Calculate local variance using a sliding window approach
    # This is a simplified version - ideally would use proper windowing
    try:
        from scipy import ndimage
        # Calculate local standard deviation using generic filter
        local_std = ndimage.generic_filter(img_array, np.std, size=7)
        high_variance_threshold = np.percentile(local_std, 75)
        high_variance_regions = local_std > high_variance_threshold
        complexity_ratio = np.sum(high_variance_regions) / high_variance_regions.size
    except ImportError:
        # Fallback: simple variance calculation
        logging.debug("SciPy not available, using simple variance")
        # Calculate variance in 7x7 patches
        h, w = img_array.shape
        local_variances = []
        
        for i in range(3, h-3, 7):  # Step by 7 for non-overlapping patches
            for j in range(3, w-3, 7):
                patch = img_array[i-3:i+4, j-3:j+4]
                local_variances.append(np.var(patch))
        
        if local_variances:
            high_variance_threshold = np.percentile(local_variances, 75)
            high_variance_count = sum(1 for v in local_variances if v > high_variance_threshold)
            complexity_ratio = high_variance_count / len(local_variances)
        else:
            complexity_ratio = 0.0
    
    return {
        'complexity_ratio': complexity_ratio,
        'mean_local_std': np.mean(local_std) if 'local_std' in locals() else 0.0
    }


def detect_geometric_patterns(original_img, result_img):
    """
    Detect presence of geometric patterns characteristic of cubism.
    Uses line detection and angular analysis.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for analysis
    orig_gray = np.array(original_img.convert('L'))
    result_gray = np.array(result_img.convert('L'))
    
    # Calculate image differences to identify new structures
    diff = np.abs(result_gray.astype(np.float32) - orig_gray.astype(np.float32))
    
    # Look for structured, geometric changes
    try:
        from scipy import ndimage
        # Apply edge detection on the difference image
        sobel_x = ndimage.sobel(diff, axis=1)
        sobel_y = ndimage.sobel(diff, axis=0)
        edge_magnitude = np.hypot(sobel_x, sobel_y)
        
        # Count strong linear edges (characteristic of geometric fragmentation)
        strong_edge_threshold = np.percentile(edge_magnitude, 90)
        strong_edges = edge_magnitude > strong_edge_threshold
        geometric_edge_ratio = np.sum(strong_edges) / strong_edges.size
        
    except ImportError:
        # Fallback geometric pattern detection
        # Look for regular patterns in the difference image
        geometric_edge_ratio = np.std(diff) / (np.mean(diff) + 1e-6)  # High std suggests fragmentation
        geometric_edge_ratio = min(geometric_edge_ratio / 50.0, 1.0)  # Normalize
    
    return {
        'geometric_edge_ratio': geometric_edge_ratio,
        'mean_difference': np.mean(diff),
        'max_difference': np.max(diff)
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
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # Pixels with >30 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 20  # At least 20% of pixels changed significantly
    }


def check_cubism_effect(traj, env_info, task_info):
    """
    Main verifier function for cubism effect task.
    Checks:
    1. Edge density increased significantly (geometric fragmentation)
    2. Texture complexity increased (fragmented regions)  
    3. Geometric patterns present (cubist structure)
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
        "/home/ga/Desktop/cubism_art.jpg",
        "/home/ga/Desktop/cubism_art.png",
        "/home/ga/Desktop/cubism_art.jpeg",
        "/home/ga/Desktop/cubism.jpg",
        "/home/ga/Desktop/art.jpg",
        "/home/ga/Desktop/cubism_photo_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/cubism_photo.jpg",
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
        
        # Analyze edge density changes
        orig_edges = analyze_edge_density(original_image)
        result_edges = analyze_edge_density(result_image)
        
        # Analyze texture complexity
        result_texture = analyze_texture_complexity(result_image)
        
        # Detect geometric patterns
        geometric_analysis = detect_geometric_patterns(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original edge density: {orig_edges['edge_density']:.3f}")
        feedback_parts.append(f"Result edge density: {result_edges['edge_density']:.3f}")
        feedback_parts.append(f"Edge increase ratio: {result_edges['edge_density'] / (orig_edges['edge_density'] + 1e-6):.2f}x")
        feedback_parts.append(f"Texture complexity: {result_texture['complexity_ratio']:.3f}")
        feedback_parts.append(f"Geometric patterns: {geometric_analysis['geometric_edge_ratio']:.3f}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Edge density increased significantly (minimum 50% increase)
        edge_increase_ratio = result_edges['edge_density'] / (orig_edges['edge_density'] + 1e-6)
        edge_increase_good = edge_increase_ratio >= 1.5
        if edge_increase_good:
            criteria_met += 1
        feedback_parts.append(f"Edge density increased: {'✅' if edge_increase_good else '❌'}")
        
        # 2. High texture complexity (fragmented regions)
        high_complexity = result_texture['complexity_ratio'] >= 0.20  # At least 20% high-variance regions
        if high_complexity:
            criteria_met += 1
        feedback_parts.append(f"High texture complexity: {'✅' if high_complexity else '❌'}")
        
        # 3. Geometric patterns present
        geometric_patterns = geometric_analysis['geometric_edge_ratio'] >= 0.05  # Significant geometric structure
        if geometric_patterns:
            criteria_met += 1
        feedback_parts.append(f"Geometric patterns: {'✅' if geometric_patterns else '❌'}")
        
        # 4. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # 5. Artistic effect applied (combined heuristic)
        artistic_effect = (edge_increase_ratio >= 1.3 and 
                          result_texture['complexity_ratio'] >= 0.15 and
                          change_analysis['change_percentage'] >= 15)
        if artistic_effect:
            criteria_met += 1
        feedback_parts.append(f"Artistic effect applied: {'✅' if artistic_effect else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (75%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent cubism effect!")
        elif passed:
            feedback_parts.append("✅ Good cubism effect!")
        else:
            feedback_parts.append("❌ Cubism effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in cubism effect verification: {e}")
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
    result = check_cubism_effect([], {}, {})
    print(f"Test result: {result}")