#!/usr/bin/env python3
"""
Verifier for GIMP neon edge effect task.
Checks if the neon edge detection filter was applied successfully.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def analyze_neon_effect(original_img, result_img):
    """
    Analyze if the neon edge effect was successfully applied.
    Returns analysis of darkness, brightness, and contrast changes.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for intensity analysis
    if original_img.mode != 'L':
        orig_gray = np.array(original_img.convert('L'))
    else:
        orig_gray = np.array(original_img)
        
    if result_img.mode != 'L':
        result_gray = np.array(result_img.convert('L'))
    else:
        result_gray = np.array(result_img)
    
    # Criterion 1: Dark background (≥60% very dark pixels)
    dark_pixels = np.sum(result_gray < 50)
    total_pixels = result_gray.size
    dark_pixels_pct = dark_pixels / total_pixels
    criterion_1 = dark_pixels_pct >= 0.60
    
    # Criterion 2: Bright edges present (≥5% bright pixels)
    bright_pixels = np.sum(result_gray > 180)
    bright_pixels_pct = bright_pixels / total_pixels
    criterion_2 = bright_pixels_pct >= 0.05
    
    # Criterion 3: Dramatically darkened (≥50% brightness reduction)
    orig_mean = np.mean(orig_gray)
    result_mean = np.mean(result_gray)
    brightness_reduction = (orig_mean - result_mean) / max(orig_mean, 1e-6)
    criterion_3 = brightness_reduction >= 0.50
    
    # Criterion 4: Contrast enhanced (std dev increase ≥30% or very high)
    orig_std = np.std(orig_gray.astype(np.float32))
    result_std = np.std(result_gray.astype(np.float32))
    std_increase = (result_std - orig_std) / max(orig_std, 1e-6)
    criterion_4 = (std_increase >= 0.30) or (result_std > 60)
    
    return {
        'dark_pixels_pct': dark_pixels_pct * 100,
        'bright_pixels_pct': bright_pixels_pct * 100,
        'brightness_reduction': brightness_reduction * 100,
        'orig_mean': orig_mean,
        'result_mean': result_mean,
        'orig_std': orig_std,
        'result_std': result_std,
        'std_increase': std_increase * 100,
        'criterion_1': criterion_1,  # Dark background
        'criterion_2': criterion_2,  # Bright edges
        'criterion_3': criterion_3,  # Dramatically darkened
        'criterion_4': criterion_4   # Contrast enhanced
    }


def check_image_changed(original_img, result_img):
    """Check if the result image is meaningfully different from original."""
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Compare arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate mean absolute difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Consider changed if mean difference > 10 intensity units
    return mean_diff > 10, mean_diff


def check_neon_effect(traj, env_info, task_info):
    """
    Main verifier function for neon edge effect task.
    Checks:
    1. Dark background (≥60% very dark pixels)
    2. Bright edges present (≥5% bright pixels)
    3. Dramatically darkened (≥50% brightness reduction)
    4. Contrast enhanced (≥30% std dev increase or >60 total)
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
        "/home/ga/Desktop/neon_effect.png",
        "/home/ga/Desktop/neon_effect.jpg", 
        "/home/ga/Desktop/neon_effect.jpeg",
        "/home/ga/Desktop/edge_photo_neon.png",
        "/home/ga/Desktop/edge_photo_edited.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/edge_photo.jpg",
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
        
        # Analyze neon effect
        analysis = analyze_neon_effect(original_image, result_image)
        
        # Check if image was meaningfully changed
        image_changed, mean_diff = check_image_changed(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Dark pixels: {analysis['dark_pixels_pct']:.1f}% (need ≥60%)")
        feedback_parts.append(f"Bright pixels: {analysis['bright_pixels_pct']:.1f}% (need ≥5%)")
        feedback_parts.append(f"Brightness reduction: {analysis['brightness_reduction']:.1f}% (need ≥50%)")
        feedback_parts.append(f"Contrast increase: {analysis['std_increase']:.1f}% (need ≥30%)")
        feedback_parts.append(f"Mean difference: {mean_diff:.1f}")
        
        # Count criteria met
        criteria_met = 0
        total_criteria = 4
        
        if analysis['criterion_1']:  # Dark background
            criteria_met += 1
        feedback_parts.append(f"Dark background: {'✅' if analysis['criterion_1'] else '❌'}")
        
        if analysis['criterion_2']:  # Bright edges
            criteria_met += 1
        feedback_parts.append(f"Bright edges present: {'✅' if analysis['criterion_2'] else '❌'}")
        
        if analysis['criterion_3']:  # Dramatically darkened
            criteria_met += 1
        feedback_parts.append(f"Dramatically darkened: {'✅' if analysis['criterion_3'] else '❌'}")
        
        if analysis['criterion_4']:  # Contrast enhanced
            criteria_met += 1
        feedback_parts.append(f"Contrast enhanced: {'✅' if analysis['criterion_4'] else '❌'}")
        
        feedback_parts.append(f"Image modified: {'✅' if image_changed else '❌'}")
        
        # Calculate success based on criteria
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect neon edge effect!")
        elif passed:
            feedback_parts.append("✅ Good neon edge effect!")
        else:
            feedback_parts.append(f"❌ Neon effect incomplete ({criteria_met}/{total_criteria} criteria met)")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in neon effect verification: {e}")
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
    result = check_neon_effect([], {}, {})
    print(f"Test result: {result}")