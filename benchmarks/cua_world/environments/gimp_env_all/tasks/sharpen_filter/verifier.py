#!/usr/bin/env python3
"""
Verifier for GIMP sharpen filter task.
Checks if the image was successfully sharpened using edge enhancement analysis.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Set up logging
logging.basicConfig(level=logging.DEBUG)

def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def calculate_sharpness_score(img):
    """
    Calculate image sharpness using Laplacian variance method.
    Higher values indicate sharper images.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    # Convert to grayscale for analysis
    img_array = np.array(img)
    if len(img_array.shape) == 3:
        gray = np.mean(img_array, axis=2)
    else:
        gray = img_array
    
    # Calculate Laplacian (edge detection)
    # Simple Laplacian kernel implementation without scipy
    height, width = gray.shape
    laplacian = np.zeros_like(gray)
    
    # Apply 3x3 Laplacian kernel manually
    kernel = np.array([[0, -1, 0], [-1, 4, -1], [0, -1, 0]], dtype=np.float32)
    
    for i in range(1, height - 1):
        for j in range(1, width - 1):
            # Extract 3x3 neighborhood
            neighborhood = gray[i-1:i+2, j-1:j+2]
            # Apply kernel
            laplacian[i, j] = np.sum(neighborhood * kernel)
    
    # Calculate variance as sharpness measure
    sharpness = np.var(laplacian)
    
    return sharpness


def calculate_edge_strength(img):
    """
    Calculate edge strength using gradient magnitude.
    Alternative sharpness measure using Sobel-like operators.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    if len(img_array.shape) == 3:
        gray = np.mean(img_array, axis=2)
    else:
        gray = img_array
    
    # Simple gradient calculation (Sobel-like)
    height, width = gray.shape
    grad_x = np.zeros_like(gray)
    grad_y = np.zeros_like(gray)
    
    # Horizontal gradient
    for i in range(height):
        for j in range(1, width - 1):
            grad_x[i, j] = gray[i, j+1] - gray[i, j-1]
    
    # Vertical gradient  
    for i in range(1, height - 1):
        for j in range(width):
            grad_y[i, j] = gray[i+1, j] - gray[i-1, j]
    
    # Gradient magnitude
    gradient_magnitude = np.sqrt(grad_x**2 + grad_y**2)
    
    # Return mean gradient strength
    return np.mean(gradient_magnitude)


def detect_sharpening_artifacts(original_img, result_img):
    """
    Detect potential over-sharpening artifacts.
    Returns True if artifacts are detected (bad sharpening).
    """
    # Calculate noise levels using standard deviation in smooth regions
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Resize if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Convert to grayscale
    orig_gray = np.mean(orig_array, axis=2) if len(orig_array.shape) == 3 else orig_array
    result_gray = np.mean(result_array, axis=2) if len(result_array.shape) == 3 else result_array
    
    # Calculate noise in smooth regions (center 50% of image)
    h, w = orig_gray.shape
    center_h_start, center_h_end = h // 4, 3 * h // 4
    center_w_start, center_w_end = w // 4, 3 * w // 4
    
    orig_center = orig_gray[center_h_start:center_h_end, center_w_start:center_w_end]
    result_center = result_gray[center_h_start:center_h_end, center_w_start:center_w_end]
    
    orig_noise = np.std(orig_center)
    result_noise = np.std(result_center)
    
    # If noise increased dramatically (>300%), likely over-sharpened
    noise_increase_ratio = result_noise / max(orig_noise, 1.0)
    over_sharpened = noise_increase_ratio > 3.0
    
    return over_sharpened, noise_increase_ratio


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of changed pixels
    if len(diff.shape) == 3:
        pixel_diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    else:
        pixel_diff_magnitude = diff
    
    changed_pixels = np.sum(pixel_diff_magnitude > 5)  # Pixels with >5 intensity change
    total_pixels = pixel_diff_magnitude.size
    change_percentage = (changed_pixels / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 2  # At least 2% of pixels changed
    }


def check_sharpen_filter(traj, env_info, task_info):
    """
    Main verifier function for sharpen filter task.
    Checks:
    1. Image sharpness increased significantly (≥10%)
    2. Edge strength improved
    3. No serious over-sharpening artifacts
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
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container paths
        container_original = "/home/ga/Desktop/blurry_image.jpg"
        possible_results = [
            "/home/ga/Desktop/sharpened_image.jpg",
            "/home/ga/Desktop/sharpened_image.png", 
            "/home/ga/Desktop/sharpened_image.jpeg",
            "/home/ga/Desktop/blurry_image_enhanced.jpg",
            "/home/ga/Desktop/enhanced.jpg"
        ]
        
        # Define host paths
        host_original = temp_path / "original.jpg"
        host_result = temp_path / "result.jpg"
        
        # Try to copy original image from container
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original image: {error}"
            }
        
        # Try to copy result image from container (try multiple possible names)
        result_found = False
        result_container_path = ""
        for result_path in possible_results:
            success, error = copy_file_from_container(copy_from_env, result_path, host_result)
            if success:
                result_found = True
                result_container_path = result_path
                logging.debug(f"Found result image at: {result_path}")
                break
        
        if not result_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result image. Tried: {[Path(p).name for p in possible_results]}"
            }
    
        try:
            # Load images from copied files
            original_image = Image.open(host_original)
            result_image = Image.open(host_result)
            
            logging.debug(f"Found result image at: {result_container_path}")
            
            # Calculate sharpness metrics
            original_sharpness = calculate_sharpness_score(original_image)
            result_sharpness = calculate_sharpness_score(result_image)
            
            # Calculate edge strength
            original_edge_strength = calculate_edge_strength(original_image)
            result_edge_strength = calculate_edge_strength(result_image)
            
            # Check for over-sharpening artifacts
            over_sharpened, noise_ratio = detect_sharpening_artifacts(original_image, result_image)
            
            # Check for meaningful change
            change_analysis = check_meaningful_change(original_image, result_image)
            
            # Calculate improvement percentages
            sharpness_improvement = ((result_sharpness - original_sharpness) / max(original_sharpness, 1.0)) * 100
            edge_improvement = ((result_edge_strength - original_edge_strength) / max(original_edge_strength, 1.0)) * 100
            
            feedback_parts = []
            feedback_parts.append(f"Original sharpness: {original_sharpness:.1f}")
            feedback_parts.append(f"Result sharpness: {result_sharpness:.1f}")
            feedback_parts.append(f"Sharpness improvement: {sharpness_improvement:.1f}%")
            feedback_parts.append(f"Edge improvement: {edge_improvement:.1f}%")
            feedback_parts.append(f"Noise ratio: {noise_ratio:.2f}")
            feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
            
            # Evaluate success criteria
            criteria_met = 0
            total_criteria = 4
            
            # 1. Sharpness increased significantly (at least 10%)
            sharpness_improved = sharpness_improvement >= 10.0
            if sharpness_improved:
                criteria_met += 1
            feedback_parts.append(f"Sharpness increased ≥10%: {'✅' if sharpness_improved else '❌'}")
            
            # 2. Edge strength improved 
            edge_strength_improved = edge_improvement >= 5.0
            if edge_strength_improved:
                criteria_met += 1
            feedback_parts.append(f"Edge strength improved: {'✅' if edge_strength_improved else '❌'}")
            
            # 3. No serious over-sharpening artifacts
            no_artifacts = not over_sharpened
            if no_artifacts:
                criteria_met += 1
            feedback_parts.append(f"No over-sharpening: {'✅' if no_artifacts else '❌'}")
            
            # 4. Image was meaningfully modified
            if change_analysis['meaningfully_changed']:
                criteria_met += 1
            feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
            
            # Calculate score and pass/fail
            score = int((criteria_met / total_criteria) * 100)
            passed = score >= 75  # Need at least 3/4 criteria
            
            if passed and score >= 90:
                feedback_parts.append("🎉 Excellent image sharpening!")
            elif passed:
                feedback_parts.append("✅ Good image sharpening!")
            else:
                feedback_parts.append("❌ Image sharpening needs improvement")
                
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


if __name__ == "__main__":
    # Test the verifier
    result = check_sharpen_filter([], {}, {})
    print(f"Test result: {result}")