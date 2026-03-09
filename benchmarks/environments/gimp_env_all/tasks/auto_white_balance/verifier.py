#!/usr/bin/env python3
"""
Verifier for GIMP auto white balance task.
Checks if automatic white balance correction was successfully applied.
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


def analyze_color_temperature(img):
    """
    Analyze color temperature of an image using R/B ratio.
    Returns temperature indicator where ~1.0 is neutral, >1.0 is warm, <1.0 is cool.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img).astype(np.float32)
    
    # Calculate channel means
    r_mean = np.mean(img_array[:, :, 0])
    g_mean = np.mean(img_array[:, :, 1])
    b_mean = np.mean(img_array[:, :, 2])
    
    # Color temperature indicator (R/B ratio)
    # Neutral ≈ 1.0, >1.0 = warm (orange/yellow), <1.0 = cool (blue)
    temp_ratio = r_mean / (b_mean + 1e-6)  # Add small value to avoid division by zero
    
    # Channel balance (standard deviation of RGB means)
    channel_balance = np.std([r_mean, g_mean, b_mean])
    
    return {
        'r_mean': r_mean,
        'g_mean': g_mean,
        'b_mean': b_mean,
        'temperature_ratio': temp_ratio,
        'channel_balance': channel_balance
    }


def detect_white_balance_correction(original_img, result_img):
    """
    Detect if effective white balance correction was applied.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Analyze color temperature for both images
    original_analysis = analyze_color_temperature(original_img)
    result_analysis = analyze_color_temperature(result_img)
    
    # Calculate temperature shift toward neutral
    original_temp_deviation = abs(original_analysis['temperature_ratio'] - 1.0)
    result_temp_deviation = abs(result_analysis['temperature_ratio'] - 1.0)
    
    # Check if temperature moved toward neutral
    temp_improved = result_temp_deviation < original_temp_deviation
    temp_improvement_amount = original_temp_deviation - result_temp_deviation
    
    # Check if channel balance improved (lower standard deviation = more balanced)
    balance_improved = result_analysis['channel_balance'] < original_analysis['channel_balance'] * 0.9
    balance_improvement_percent = ((original_analysis['channel_balance'] - result_analysis['channel_balance']) / 
                                 original_analysis['channel_balance']) * 100 if original_analysis['channel_balance'] > 0 else 0
    
    # Check if neutrality was enhanced overall
    neutrality_enhanced = temp_improved and balance_improved
    
    return {
        'original_temp_ratio': original_analysis['temperature_ratio'],
        'result_temp_ratio': result_analysis['temperature_ratio'],
        'original_balance': original_analysis['channel_balance'],
        'result_balance': result_analysis['channel_balance'],
        'temp_improved': temp_improved,
        'temp_improvement': temp_improvement_amount,
        'balance_improved': balance_improved,
        'balance_improvement_percent': balance_improvement_percent,
        'neutrality_enhanced': neutrality_enhanced
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
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 15)  # Pixels with >15 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage >= 15  # At least 15% of pixels changed
    }


def check_auto_white_balance(traj, env_info, task_info):
    """
    Main verifier function for auto white balance task.
    Checks:
    1. Color temperature shifted toward neutral
    2. Channel balance improved
    3. Overall neutrality was enhanced
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
        "/home/ga/Desktop/white_balanced.jpg",
        "/home/ga/Desktop/white_balanced.png", 
        "/home/ga/Desktop/white_balanced.jpeg",
        "/home/ga/Desktop/color_cast_photo_balanced.jpg",
        "/home/ga/Desktop/color_cast_photo_corrected.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/color_cast_photo.jpg",
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
        
        # Analyze white balance correction
        wb_analysis = detect_white_balance_correction(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original temp ratio: {wb_analysis['original_temp_ratio']:.3f}")
        feedback_parts.append(f"Result temp ratio: {wb_analysis['result_temp_ratio']:.3f}")
        feedback_parts.append(f"Original balance: {wb_analysis['original_balance']:.1f}")
        feedback_parts.append(f"Result balance: {wb_analysis['result_balance']:.1f}")
        feedback_parts.append(f"Balance improvement: {wb_analysis['balance_improvement_percent']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Color temperature shifted toward neutral
        if wb_analysis['temp_improved']:
            criteria_met += 1
        feedback_parts.append(f"Temperature improved: {'✅' if wb_analysis['temp_improved'] else '❌'}")
        
        # 2. Channel balance improved by at least 10%
        if wb_analysis['balance_improvement_percent'] >= 10:
            criteria_met += 1
        feedback_parts.append(f"Channel balance improved ≥10%: {'✅' if wb_analysis['balance_improvement_percent'] >= 10 else '❌'}")
        
        # 3. Overall neutrality enhanced
        if wb_analysis['neutrality_enhanced']:
            criteria_met += 1
        feedback_parts.append(f"Neutrality enhanced: {'✅' if wb_analysis['neutrality_enhanced'] else '❌'}")
        
        # 4. Image meaningfully changed
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent white balance correction!")
        elif passed:
            feedback_parts.append("✅ Good white balance correction!")
        else:
            feedback_parts.append("❌ White balance correction needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in auto white balance verification: {e}")
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
    result = check_auto_white_balance([], {}, {})
    print(f"Test result: {result}")