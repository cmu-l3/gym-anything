#!/usr/bin/env python3
"""
Verifier for GIMP add noise task.
Checks if RGB noise was successfully added to the image using statistical analysis.
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


def calculate_image_variance(img):
    """Calculate standard deviation (variance) for each RGB channel."""
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img).astype(np.float32)
    
    # Calculate standard deviation per channel
    std_per_channel = np.std(img_array, axis=(0, 1))  # Shape: (3,) for RGB
    avg_std = np.mean(std_per_channel)
    
    return {
        'per_channel_std': std_per_channel,
        'average_std': avg_std,
        'red_std': std_per_channel[0],
        'green_std': std_per_channel[1], 
        'blue_std': std_per_channel[2]
    }


def calculate_local_variance(img_array, window_size=5):
    """Calculate local variance in sliding windows to detect texture."""
    try:
        from scipy.ndimage import generic_filter
        
        def local_std(x):
            return np.std(x) if len(x) > 1 else 0
        
        # Calculate local variance for each channel
        local_vars = []
        for channel in range(3):
            channel_data = img_array[:, :, channel]
            local_var = generic_filter(channel_data, local_std, size=window_size)
            local_vars.append(local_var)
        
        return np.stack(local_vars, axis=2)
    
    except ImportError:
        # Fallback: simple grid-based local variance
        height, width, channels = img_array.shape
        local_vars = np.zeros_like(img_array)
        
        half_window = window_size // 2
        for y in range(height):
            for x in range(width):
                y1 = max(0, y - half_window)
                y2 = min(height, y + half_window + 1)
                x1 = max(0, x - half_window)
                x2 = min(width, x + half_window + 1)
                
                for c in range(channels):
                    window = img_array[y1:y2, x1:x2, c]
                    local_vars[y, x, c] = np.std(window) if window.size > 1 else 0
        
        return local_vars


def detect_noise_addition(original_img, result_img):
    """
    Detect and quantify added noise using statistical analysis.
    Returns metrics about noise increase.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Calculate global variance
    orig_variance = calculate_image_variance(original_img)
    result_variance = calculate_image_variance(result_img)
    
    # Calculate variance increase percentage
    std_increase_per_channel = ((result_variance['per_channel_std'] - orig_variance['per_channel_std']) / 
                               orig_variance['per_channel_std']) * 100
    avg_std_increase = np.mean(std_increase_per_channel)
    
    # Calculate local variance (texture analysis)
    orig_array = np.array(original_img).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    orig_local_var = calculate_local_variance(orig_array)
    result_local_var = calculate_local_variance(result_array)
    
    local_var_increase = np.mean(result_local_var) - np.mean(orig_local_var)
    
    # Check if all channels were affected
    min_channel_increase = np.min(std_increase_per_channel)
    
    return {
        'avg_std_increase': avg_std_increase,
        'per_channel_increase': std_increase_per_channel,
        'min_channel_increase': min_channel_increase,
        'local_variance_increase': local_var_increase,
        'orig_avg_std': orig_variance['average_std'],
        'result_avg_std': result_variance['average_std']
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
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 15)  # Pixels with >15 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed
    }


def check_noise_addition(traj, env_info, task_info):
    """
    Main verifier function for noise addition task.
    Checks:
    1. Standard deviation increased significantly (10-50%)
    2. Local variance increased (texture added)
    3. All RGB channels affected
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
        "/home/ga/Desktop/noisy_image.jpg",
        "/home/ga/Desktop/noisy_image.png",
        "/home/ga/Desktop/noisy_image.jpeg",
        "/home/ga/Desktop/clean_image_noisy.jpg",
        "/home/ga/Desktop/clean_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/clean_image.jpg",
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
        
        # Analyze noise addition
        noise_analysis = detect_noise_addition(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original avg std: {noise_analysis['orig_avg_std']:.2f}")
        feedback_parts.append(f"Result avg std: {noise_analysis['result_avg_std']:.2f}")
        feedback_parts.append(f"Std increase: {noise_analysis['avg_std_increase']:.1f}%")
        feedback_parts.append(f"Local variance increase: {noise_analysis['local_variance_increase']:.2f}")
        feedback_parts.append(f"Min channel increase: {noise_analysis['min_channel_increase']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Standard deviation increased appropriately (10-200%)
        std_increase_good = 10 <= noise_analysis['avg_std_increase'] <= 200
        if std_increase_good:
            criteria_met += 1
        feedback_parts.append(f"Noise variance increased: {'✅' if std_increase_good else '❌'}")
        
        # 2. Local variance increased (texture added)
        texture_added = noise_analysis['local_variance_increase'] >= 2.0
        if texture_added:
            criteria_met += 1
        feedback_parts.append(f"Texture added: {'✅' if texture_added else '❌'}")
        
        # 3. All channels affected (RGB noise should affect all channels)
        all_channels_affected = noise_analysis['min_channel_increase'] >= 5.0
        if all_channels_affected:
            criteria_met += 1
        feedback_parts.append(f"All RGB channels affected: {'✅' if all_channels_affected else '❌'}")
        
        # 4. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent noise addition!")
        elif passed:
            feedback_parts.append("✅ Good noise addition!")
        else:
            if noise_analysis['avg_std_increase'] < 10:
                feedback_parts.append("❌ Noise too weak or not added")
            elif noise_analysis['avg_std_increase'] > 200:
                feedback_parts.append("❌ Excessive noise added")
            else:
                feedback_parts.append("❌ Noise addition needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in noise addition verification: {e}")
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
    result = check_noise_addition([], {}, {})
    print(f"Test result: {result}")