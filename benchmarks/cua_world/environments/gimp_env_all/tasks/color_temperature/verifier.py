#!/usr/bin/env python3
"""
Verifier for GIMP color temperature adjustment task.
Checks if color temperature was successfully adjusted to warm up or cool down the image.
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


def analyze_color_temperature_shift(original_img, result_img):
    """
    Analyzes color temperature shift between original and result images.
    Uses yellow-blue axis as primary temperature indicator.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    # Calculate Yellow-Blue index: (R + G - 2*B) / 2
    # Positive values = warmer (yellow), Negative values = cooler (blue)
    orig_yb = (orig_array[:,:,0] + orig_array[:,:,1] - 2 * orig_array[:,:,2]) / 2
    result_yb = (result_array[:,:,0] + result_array[:,:,1] - 2 * result_array[:,:,2]) / 2
    
    # Calculate mean temperature shift
    orig_yb_mean = np.mean(orig_yb)
    result_yb_mean = np.mean(result_yb)
    temperature_delta = result_yb_mean - orig_yb_mean
    
    # Also check red-cyan axis for additional validation
    orig_rc = (2 * orig_array[:,:,0] - orig_array[:,:,1] - orig_array[:,:,2]) / 2
    result_rc = (2 * result_array[:,:,0] - result_array[:,:,1] - result_array[:,:,2]) / 2
    
    red_shift = np.mean(result_rc) - np.mean(orig_rc)
    
    # Check for clipping (pixels hitting 0 or 255 boundaries)
    clipping_percentage = (np.sum(result_array >= 255) + np.sum(result_array <= 0)) / result_array.size * 100
    
    # Calculate overall channel mean shifts
    r_shift = np.mean(result_array[:,:,0]) - np.mean(orig_array[:,:,0])
    g_shift = np.mean(result_array[:,:,1]) - np.mean(orig_array[:,:,1])
    b_shift = np.mean(result_array[:,:,2]) - np.mean(orig_array[:,:,2])
    
    return {
        'temperature_delta': temperature_delta,
        'direction': 'warmer' if temperature_delta > 0 else 'cooler',
        'magnitude': abs(temperature_delta),
        'red_shift': red_shift,
        'clipping_percentage': clipping_percentage,
        'significant_change': abs(temperature_delta) > 10,
        'r_channel_shift': r_shift,
        'g_channel_shift': g_shift,
        'b_channel_shift': b_shift
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
        'meaningfully_changed': change_percentage > 3  # At least 3% of pixels changed significantly
    }


def check_color_temperature(traj, env_info, task_info):
    """
    Main verifier function for color temperature adjustment task.
    Checks:
    1. Color temperature was significantly shifted (yellow-blue axis change)
    2. Change is in correct direction (warmer for this task)
    3. Sufficient magnitude of adjustment
    4. Quality preserved (no severe clipping)
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
        "/home/ga/Desktop/temperature_adjusted.jpg",
        "/home/ga/Desktop/temperature_adjusted.png",
        "/home/ga/Desktop/temperature_adjusted.jpeg",
        "/home/ga/Desktop/photo_with_cast_adjusted.jpg",
        "/home/ga/Desktop/warm_photo.jpg",
        "/home/ga/Desktop/photo_warmed.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_with_cast.jpg",
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
        
        # Analyze color temperature shift
        temp_analysis = analyze_color_temperature_shift(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Temperature delta: {temp_analysis['temperature_delta']:.1f}")
        feedback_parts.append(f"Direction: {temp_analysis['direction']}")
        feedback_parts.append(f"Magnitude: {temp_analysis['magnitude']:.1f}")
        feedback_parts.append(f"Clipping: {temp_analysis['clipping_percentage']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Temperature change detected (significant shift on yellow-blue axis)
        temp_change_significant = temp_analysis['significant_change']
        if temp_change_significant:
            criteria_met += 1
        feedback_parts.append(f"Temperature shifted significantly: {'✅' if temp_change_significant else '❌'}")
        
        # 2. Correct direction (warming for this task - positive delta)
        correct_direction = temp_analysis['temperature_delta'] > 5  # At least +5 units warmer
        if correct_direction:
            criteria_met += 1
        feedback_parts.append(f"Warmed up correctly: {'✅' if correct_direction else '❌'}")
        
        # 3. Sufficient magnitude (at least 15 units change)
        sufficient_magnitude = temp_analysis['magnitude'] >= 15
        if sufficient_magnitude:
            criteria_met += 1
        feedback_parts.append(f"Sufficient magnitude: {'✅' if sufficient_magnitude else '❌'}")
        
        # 4. Quality preserved (less than 2% clipping)
        quality_preserved = temp_analysis['clipping_percentage'] < 2.0
        if quality_preserved:
            criteria_met += 1
        feedback_parts.append(f"Quality preserved: {'✅' if quality_preserved else '❌'}")
        
        # 5. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (75%)
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent color temperature adjustment!")
        elif passed:
            feedback_parts.append("✅ Good color temperature adjustment!")
        else:
            feedback_parts.append("❌ Color temperature adjustment needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color temperature verification: {e}")
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
    result = check_color_temperature([], {}, {})
    print(f"Test result: {result}")