#!/usr/bin/env python3
"""
Verifier for GIMP pixelize task.
Checks if pixelize filter was applied to create uniform color blocks.
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


def calculate_local_variance(image_array, window_size=10):
    """Calculate average local variance across the image."""
    if len(image_array.shape) == 3:
        # Convert to grayscale for variance calculation
        image_gray = np.mean(image_array, axis=2)
    else:
        image_gray = image_array
    
    height, width = image_gray.shape
    variances = []
    
    # Slide window across image
    for y in range(0, height - window_size, window_size // 2):
        for x in range(0, width - window_size, window_size // 2):
            window = image_gray[y:y+window_size, x:x+window_size]
            if window.size > 0:
                variances.append(np.var(window))
    
    return np.mean(variances) if variances else 0


def detect_block_uniformity(image_array, block_size=10):
    """Detect presence of uniform color blocks characteristic of pixelization."""
    if len(image_array.shape) == 3:
        height, width, channels = image_array.shape
    else:
        height, width = image_array.shape
        channels = 1
    
    uniform_blocks = 0
    total_blocks = 0
    
    # Sample grid positions aligned with expected block boundaries
    for y in range(0, height - block_size, block_size):
        for x in range(0, width - block_size, block_size):
            block = image_array[y:y+block_size, x:x+block_size]
            
            if block.size > 0:
                # Calculate variance within this block
                if len(block.shape) == 3:
                    # For color images, calculate variance per channel and average
                    channel_variances = [np.var(block[:, :, c]) for c in range(channels)]
                    variance = np.mean(channel_variances)
                else:
                    variance = np.var(block)
                
                # Uniform blocks have very low variance (< 20 for 8-bit images)
                if variance < 20:
                    uniform_blocks += 1
                total_blocks += 1
    
    if total_blocks == 0:
        return 0
    
    uniformity_percentage = (uniform_blocks / total_blocks) * 100
    return uniformity_percentage


def analyze_pixelization_quality(original_img, result_img):
    """
    Analyze the quality of pixelization by comparing original and result images.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB for consistent processing
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate local variance for both images
    orig_variance = calculate_local_variance(orig_array, window_size=10)
    result_variance = calculate_local_variance(result_array, window_size=10)
    
    # Calculate variance reduction
    if orig_variance > 0:
        variance_reduction = ((orig_variance - result_variance) / orig_variance) * 100
    else:
        variance_reduction = 0
    
    # Detect block uniformity in result
    uniformity_percentage = detect_block_uniformity(result_array, block_size=10)
    
    # Check for meaningful modification
    pixel_diff = np.mean(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)))
    meaningfully_changed = pixel_diff > 15  # At least 15 units average difference
    
    # Calculate overall modification percentage
    diff_array = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    significant_changes = np.sum(np.sqrt(np.sum(diff_array ** 2, axis=2)) > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    modification_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'original_variance': orig_variance,
        'result_variance': result_variance,
        'variance_reduction': variance_reduction,
        'uniformity_percentage': uniformity_percentage,
        'meaningfully_changed': meaningfully_changed,
        'modification_percentage': modification_percentage,
        'average_pixel_diff': pixel_diff
    }


def check_pixelize(traj, env_info, task_info):
    """
    Main verifier function for pixelize task.
    Checks:
    1. Significant variance reduction (at least 60%)
    2. Block uniformity detected (at least 40% of blocks uniform)
    3. Substantial modification (image clearly changed)
    4. Consistent effect (pixelization applied uniformly)
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
        "/home/ga/Desktop/pixelated_image.png",
        "/home/ga/Desktop/pixelated_image.jpg",
        "/home/ga/Desktop/pixelated_image.jpeg",
        "/home/ga/Desktop/sample_image_pixelated.png",
        "/home/ga/Desktop/sample_pixelated.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/sample_image.jpg",
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
        
        # Analyze pixelization quality
        analysis = analyze_pixelization_quality(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original variance: {analysis['original_variance']:.2f}")
        feedback_parts.append(f"Result variance: {analysis['result_variance']:.2f}")
        feedback_parts.append(f"Variance reduction: {analysis['variance_reduction']:.1f}%")
        feedback_parts.append(f"Block uniformity: {analysis['uniformity_percentage']:.1f}%")
        feedback_parts.append(f"Modification: {analysis['modification_percentage']:.1f}%")
        feedback_parts.append(f"Avg pixel diff: {analysis['average_pixel_diff']:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant variance reduction (at least 60%)
        variance_reduction_good = analysis['variance_reduction'] >= 60.0
        if variance_reduction_good:
            criteria_met += 1
        feedback_parts.append(f"Variance reduced ≥60%: {'✅' if variance_reduction_good else '❌'}")
        
        # 2. Block uniformity detected (at least 40% of blocks uniform)
        uniformity_good = analysis['uniformity_percentage'] >= 40.0
        if uniformity_good:
            criteria_met += 1
        feedback_parts.append(f"Block uniformity ≥40%: {'✅' if uniformity_good else '❌'}")
        
        # 3. Substantial modification (clear changes from original)
        substantially_modified = analysis['modification_percentage'] >= 15.0
        if substantially_modified:
            criteria_met += 1
        feedback_parts.append(f"Substantially modified: {'✅' if substantially_modified else '❌'}")
        
        # 4. Meaningful change (image actually different)
        if analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect pixelization!")
        elif passed:
            feedback_parts.append("✅ Good pixelization!")
        else:
            feedback_parts.append("❌ Pixelization needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in pixelize verification: {e}")
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
    result = check_pixelize([], {}, {})
    print(f"Test result: {result}")