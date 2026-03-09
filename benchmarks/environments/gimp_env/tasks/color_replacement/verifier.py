#!/usr/bin/env python3
"""
Verifier for GIMP color replacement task.
Checks if red color was successfully replaced with blue color.
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


def analyze_color_distribution(img, color_ranges):
    """
    Analyze color distribution in image for specified color ranges.
    Returns the percentage of pixels in each color range.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    total_pixels = img_array.shape[0] * img_array.shape[1]
    
    color_stats = {}
    
    for color_name, (r_range, g_range, b_range) in color_ranges.items():
        # Create mask for pixels within the color range
        r_mask = (img_array[:, :, 0] >= r_range[0]) & (img_array[:, :, 0] <= r_range[1])
        g_mask = (img_array[:, :, 1] >= g_range[0]) & (img_array[:, :, 1] <= g_range[1])
        b_mask = (img_array[:, :, 2] >= b_range[0]) & (img_array[:, :, 2] <= b_range[1])
        
        # Combine masks
        color_mask = r_mask & g_mask & b_mask
        color_pixels = np.sum(color_mask)
        color_percentage = (color_pixels / total_pixels) * 100
        
        color_stats[color_name] = {
            'pixels': color_pixels,
            'percentage': color_percentage
        }
    
    return color_stats


def detect_red_to_blue_replacement(original_img, result_img):
    """
    Detect if red color was successfully replaced with blue.
    """
    # Define color ranges for red and blue
    color_ranges = {
        'red': ((120, 255), (0, 100), (0, 100)),        # Red: high R, low G, low B
        'blue': ((0, 100), (0, 120), (120, 255)),       # Blue: low R, low G, high B
        'dark_red': ((80, 160), (0, 60), (0, 60)),      # Dark red tones
        'dark_blue': ((0, 60), (0, 80), (80, 200)),     # Dark blue tones
    }
    
    # Analyze color distribution in both images
    original_colors = analyze_color_distribution(original_img, color_ranges)
    result_colors = analyze_color_distribution(result_img, color_ranges)
    
    # Calculate changes
    red_reduction = original_colors['red']['percentage'] - result_colors['red']['percentage']
    dark_red_reduction = original_colors['dark_red']['percentage'] - result_colors['dark_red']['percentage']
    blue_increase = result_colors['blue']['percentage'] - original_colors['blue']['percentage']
    dark_blue_increase = result_colors['dark_blue']['percentage'] - original_colors['dark_blue']['percentage']
    
    total_red_reduction = red_reduction + dark_red_reduction
    total_blue_increase = blue_increase + dark_blue_increase
    
    return {
        'original_red': original_colors['red']['percentage'] + original_colors['dark_red']['percentage'],
        'result_red': result_colors['red']['percentage'] + result_colors['dark_red']['percentage'],
        'original_blue': original_colors['blue']['percentage'] + original_colors['dark_blue']['percentage'], 
        'result_blue': result_colors['blue']['percentage'] + result_colors['dark_blue']['percentage'],
        'red_reduction': total_red_reduction,
        'blue_increase': total_blue_increase,
        'color_shift_ratio': total_blue_increase / max(total_red_reduction, 0.1)  # Avoid division by zero
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
        'meaningfully_changed': change_percentage > 5  # At least 5% of pixels changed significantly
    }


def check_color_replacement(traj, env_info, task_info):
    """
    Main verifier function for color replacement task.
    Checks:
    1. Red color was significantly reduced
    2. Blue color was significantly increased
    3. The color shift ratio indicates successful replacement
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
        "/home/ga/Desktop/red_to_blue_car.jpg",
        "/home/ga/Desktop/red_to_blue_car.png",
        "/home/ga/Desktop/blue_car.jpg",
        "/home/ga/Desktop/red_to_blue_car.jpeg",
        "/home/ga/Desktop/car_blue.jpg",
        "/home/ga/Desktop/red_car_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/red_car_image.jpg",
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
        
        # Analyze color replacement
        color_analysis = detect_red_to_blue_replacement(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original red: {color_analysis['original_red']:.1f}%")
        feedback_parts.append(f"Result red: {color_analysis['result_red']:.1f}%")
        feedback_parts.append(f"Original blue: {color_analysis['original_blue']:.1f}%")
        feedback_parts.append(f"Result blue: {color_analysis['result_blue']:.1f}%")
        feedback_parts.append(f"Red reduction: {color_analysis['red_reduction']:.1f}%")
        feedback_parts.append(f"Blue increase: {color_analysis['blue_increase']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant red reduction (at least 2% or 50% of original red)
        red_reduction_significant = (color_analysis['red_reduction'] >= 2.0 or 
                                   color_analysis['red_reduction'] >= color_analysis['original_red'] * 0.5)
        if red_reduction_significant:
            criteria_met += 1
        feedback_parts.append(f"Red reduced significantly: {'✅' if red_reduction_significant else '❌'}")
        
        # 2. Blue increase (at least 1%)
        blue_increase_good = color_analysis['blue_increase'] >= 1.0
        if blue_increase_good:
            criteria_met += 1
        feedback_parts.append(f"Blue increased: {'✅' if blue_increase_good else '❌'}")
        
        # 3. Good color shift ratio (blue increase should correlate with red decrease)
        good_shift_ratio = 0.3 <= color_analysis['color_shift_ratio'] <= 3.0
        if good_shift_ratio:
            criteria_met += 1
        feedback_parts.append(f"Good color shift ratio: {'✅' if good_shift_ratio else '❌'}")
        
        # 4. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent color replacement!")
        elif passed:
            feedback_parts.append("✅ Good color replacement!")
        else:
            feedback_parts.append("❌ Color replacement needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color replacement verification: {e}")
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
    result = check_color_replacement([], {}, {})
    print(f"Test result: {result}")
