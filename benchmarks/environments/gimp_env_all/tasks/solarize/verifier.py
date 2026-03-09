#!/usr/bin/env python3
"""
Verifier for GIMP solarize effect task.
Checks if solarization was applied correctly by analyzing brightness patterns.
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


def analyze_brightness_patterns(original_img, result_img):
    """
    Analyze brightness patterns to detect solarization effect.
    Solarization inverts tones above a threshold (typically ~127).
    """
    # Convert to grayscale for luminosity analysis
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
    
    orig_array = np.array(orig_gray, dtype=np.float32)
    result_array = np.array(result_gray, dtype=np.float32)
    
    # Define brightness threshold (typically 127 for mid-point)
    threshold = 127
    
    # Analyze bright regions (should be darkened in solarization)
    bright_mask = orig_array > threshold
    bright_region_analysis = {
        'pixels_count': np.sum(bright_mask),
        'darkened': False,
        'darkening_percentage': 0.0
    }
    
    if np.sum(bright_mask) > 0:
        bright_orig = orig_array[bright_mask]
        bright_result = result_array[bright_mask]
        
        # Calculate average darkening
        bright_darkening = np.mean(bright_orig - bright_result)
        bright_region_analysis['darkening_percentage'] = bright_darkening / 255.0
        bright_region_analysis['darkened'] = bright_darkening > 76.5  # ~30% darkening
    
    # Analyze dark regions (should remain similar in solarization)
    dark_mask = orig_array <= threshold
    dark_region_analysis = {
        'pixels_count': np.sum(dark_mask),
        'preserved': False,
        'preservation_percentage': 0.0
    }
    
    if np.sum(dark_mask) > 0:
        dark_orig = orig_array[dark_mask]
        dark_result = result_array[dark_mask]
        
        # Calculate average change (should be minimal)
        dark_change = np.mean(np.abs(dark_orig - dark_result))
        dark_region_analysis['preservation_percentage'] = 1.0 - (dark_change / 255.0)
        dark_region_analysis['preserved'] = dark_change < 51  # <20% change
    
    return bright_region_analysis, dark_region_analysis


def check_not_simple_inversion(original_img, result_img):
    """
    Verify that the result is solarization, not simple color inversion.
    """
    # Convert to grayscale
    orig_gray = np.array(original_img.convert('L'), dtype=np.float32)
    result_gray = np.array(result_img.convert('L'), dtype=np.float32)
    
    if orig_gray.shape != result_gray.shape:
        result_gray = np.array(result_img.convert('L').resize(original_img.size), dtype=np.float32)
    
    # Create complete inversion
    inverted = 255 - orig_gray
    
    # Calculate similarity to complete inversion
    inversion_diff = np.mean(np.abs(inverted - result_gray))
    inversion_similarity = 1.0 - (inversion_diff / 255.0)
    
    # Solarization should be different from simple inversion
    not_simple_inversion = inversion_similarity < 0.85  # Less than 85% similar to inversion
    
    return not_simple_inversion, inversion_similarity


def check_meaningful_modification(original_img, result_img):
    """
    Check if the image was meaningfully modified.
    """
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img, dtype=np.float32)
    result_array = np.array(result_img, dtype=np.float32)
    
    # Calculate pixel-wise differences
    if len(orig_array.shape) == 3:  # Color image
        diff = np.sqrt(np.sum((orig_array - result_array) ** 2, axis=2))
    else:  # Grayscale
        diff = np.abs(orig_array - result_array)
    
    # Count significantly changed pixels
    significant_changes = np.sum(diff > 30)  # >30 intensity units
    total_pixels = diff.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    meaningfully_modified = change_percentage > 15  # At least 15% pixels changed
    
    return meaningfully_modified, change_percentage


def check_solarize(traj, env_info, task_info):
    """
    Main verifier function for solarize effect task.
    Checks:
    1. Bright regions were significantly darkened
    2. Dark regions remained relatively unchanged
    3. Result is not simple color inversion
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
        "/home/ga/Desktop/solarized_image.jpg",
        "/home/ga/Desktop/solarized_image.png",
        "/home/ga/Desktop/solarized_image.jpeg",
        "/home/ga/Desktop/landscape_bright_solarized.jpg",
        "/home/ga/Desktop/landscape_solarize.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_bright.jpg",
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
        
        # Analyze brightness patterns for solarization
        bright_analysis, dark_analysis = analyze_brightness_patterns(original_image, result_image)
        
        # Check if it's not simple inversion
        not_inversion, inversion_similarity = check_not_simple_inversion(original_image, result_image)
        
        # Check for meaningful modification
        meaningfully_modified, change_percentage = check_meaningful_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Bright pixels: {bright_analysis['pixels_count']}")
        feedback_parts.append(f"Dark pixels: {dark_analysis['pixels_count']}")
        feedback_parts.append(f"Bright regions darkened: {'✅' if bright_analysis['darkened'] else '❌'}")
        feedback_parts.append(f"Darkening: {bright_analysis['darkening_percentage']*100:.1f}%")
        feedback_parts.append(f"Dark regions preserved: {'✅' if dark_analysis['preserved'] else '❌'}")
        feedback_parts.append(f"Preservation: {dark_analysis['preservation_percentage']*100:.1f}%")
        feedback_parts.append(f"Not simple inversion: {'✅' if not_inversion else '❌'}")
        feedback_parts.append(f"Inversion similarity: {inversion_similarity*100:.1f}%")
        feedback_parts.append(f"Meaningfully modified: {'✅' if meaningfully_modified else '❌'}")
        feedback_parts.append(f"Pixels changed: {change_percentage:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Bright regions darkened (at least 30% darkening)
        if bright_analysis['darkened']:
            criteria_met += 1
        
        # 2. Dark regions preserved (<20% change)
        if dark_analysis['preserved']:
            criteria_met += 1
        
        # 3. Not simple inversion
        if not_inversion:
            criteria_met += 1
        
        # 4. Meaningfully modified
        if meaningfully_modified:
            criteria_met += 1
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect solarization effect!")
        elif passed:
            feedback_parts.append("✅ Good solarization applied!")
        else:
            feedback_parts.append("❌ Solarization effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in solarize verification: {e}")
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
    result = check_solarize([], {}, {})
    print(f"Test result: {result}")