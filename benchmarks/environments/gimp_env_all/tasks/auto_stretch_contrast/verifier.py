#!/usr/bin/env python3
"""
Verifier for GIMP auto-stretch contrast task.
Checks if contrast stretching was successfully applied by analyzing histogram expansion and contrast improvement.
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


def analyze_histogram_expansion(original_img, result_img):
    """
    Analyze whether the histogram was properly expanded (stretched) to use more of the full 0-255 range.
    """
    # Convert to grayscale for tonal analysis
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    orig_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    # Calculate histogram statistics
    orig_min, orig_max = np.min(orig_array), np.max(orig_array)
    result_min, result_max = np.min(result_array), np.max(result_array)
    
    # Calculate dynamic range (min to max spread)
    orig_range = orig_max - orig_min
    result_range = result_max - result_min
    
    # Calculate standard deviation (measure of contrast)
    orig_std = np.std(orig_array)
    result_std = np.std(result_array)
    
    # Calculate percentile-based effective range (robust to outliers)
    orig_p5, orig_p95 = np.percentile(orig_array, [5, 95])
    result_p5, result_p95 = np.percentile(result_array, [5, 95])
    orig_eff_range = orig_p95 - orig_p5
    result_eff_range = result_p95 - result_p5
    
    return {
        'orig_min': orig_min,
        'orig_max': orig_max,
        'result_min': result_min,
        'result_max': result_max,
        'orig_range': orig_range,
        'result_range': result_range,
        'orig_std': orig_std,
        'result_std': result_std,
        'orig_eff_range': orig_eff_range,
        'result_eff_range': result_eff_range,
        'range_increase_pct': ((result_range - orig_range) / orig_range) * 100 if orig_range > 0 else 0,
        'std_increase_pct': ((result_std - orig_std) / orig_std) * 100 if orig_std > 0 else 0,
        'eff_range_increase_pct': ((result_eff_range - orig_eff_range) / orig_eff_range) * 100 if orig_eff_range > 0 else 0
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different (contrast was actually applied)."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for comparison
    orig_gray = np.array(original_img.convert('L'))
    result_gray = np.array(result_img.convert('L'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_gray.astype(np.float32) - result_gray.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(diff > 10)  # Pixels with >10 intensity change
    total_pixels = orig_gray.size
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed
    }


def check_auto_stretch_contrast(traj, env_info, task_info):
    """
    Main verifier function for auto-stretch contrast task.
    Checks:
    1. Increased standard deviation (better contrast)
    2. Expanded dynamic range (min-to-max spread)
    3. Black point moved closer to 0 (darker darks)
    4. White point moved closer to 255 (brighter brights)
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
        "/home/ga/Desktop/contrast_stretched.jpg",
        "/home/ga/Desktop/contrast_stretched.png", 
        "/home/ga/Desktop/contrast_stretched.jpeg",
        "/home/ga/Desktop/flat_image_stretched.jpg",
        "/home/ga/Desktop/flat_image_contrast.jpg",
        "/home/ga/Desktop/stretched.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flat_image.jpg",
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
        
        # Analyze histogram expansion
        histogram_analysis = analyze_histogram_expansion(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original range: {histogram_analysis['orig_min']}-{histogram_analysis['orig_max']} ({histogram_analysis['orig_range']})")
        feedback_parts.append(f"Result range: {histogram_analysis['result_min']}-{histogram_analysis['result_max']} ({histogram_analysis['result_range']})")
        feedback_parts.append(f"Original std: {histogram_analysis['orig_std']:.1f}")
        feedback_parts.append(f"Result std: {histogram_analysis['result_std']:.1f}")
        feedback_parts.append(f"Range increase: {histogram_analysis['range_increase_pct']:.1f}%")
        feedback_parts.append(f"Contrast increase: {histogram_analysis['std_increase_pct']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Increased standard deviation (at least 20% improvement in contrast)
        std_increased = histogram_analysis['std_increase_pct'] >= 20
        if std_increased:
            criteria_met += 1
        feedback_parts.append(f"Contrast increased (≥20%): {'✅' if std_increased else '❌'}")
        
        # 2. Expanded dynamic range (at least 15% or approaching full range)
        range_expanded = (histogram_analysis['range_increase_pct'] >= 15 or 
                         histogram_analysis['result_range'] >= 240)
        if range_expanded:
            criteria_met += 1
        feedback_parts.append(f"Range expanded: {'✅' if range_expanded else '❌'}")
        
        # 3. Black point darkened (moved closer to 0, with tolerance)
        blacks_darkened = histogram_analysis['result_min'] <= histogram_analysis['orig_min'] + 5
        if blacks_darkened:
            criteria_met += 1
        feedback_parts.append(f"Blacks darkened: {'✅' if blacks_darkened else '❌'}")
        
        # 4. White point brightened (moved closer to 255, with tolerance)
        whites_brightened = histogram_analysis['result_max'] >= histogram_analysis['orig_max'] - 5
        if whites_brightened:
            criteria_met += 1
        feedback_parts.append(f"Whites brightened: {'✅' if whites_brightened else '❌'}")
        
        # 5. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%), but using 75% threshold
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent contrast stretching!")
        elif passed:
            feedback_parts.append("✅ Good contrast stretching!")
        else:
            feedback_parts.append("❌ Contrast stretching needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in auto-stretch contrast verification: {e}")
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
    result = check_auto_stretch_contrast([], {}, {})
    print(f"Test result: {result}")