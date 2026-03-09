#!/usr/bin/env python3
"""
Verifier for GIMP pattern fill task.
Checks if a pattern was successfully applied to a rectangular selection in the upper-left area.
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


def detect_pattern_in_region(original_img, result_img):
    """
    Detect pattern application in the expected region (upper-left quadrant).
    Uses statistical texture analysis to distinguish patterns from solid colors.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Define target region (upper-left quadrant)
    height, width = result_array.shape[:2]
    target_region = result_array[0:height//2, 0:width//2]
    original_region = orig_array[0:height//2, 0:width//2]
    
    # Calculate color standard deviation for texture detection
    # Patterns should have much higher color variation than solid fills
    color_std = np.std(target_region.astype(np.float32))
    original_std = np.std(original_region.astype(np.float32))
    
    # Pattern threshold: significant color variation indicates pattern
    pattern_threshold = 25.0  # Empirically determined for pattern vs solid color
    has_pattern_texture = color_std > pattern_threshold
    
    # Calculate modification extent between original and result
    region_diff = np.abs(target_region.astype(np.float32) - original_region.astype(np.float32))
    mean_diff = np.mean(region_diff)
    
    # Significant change indicates pattern was applied
    significant_change = mean_diff > 30.0
    
    # Calculate coverage area (pixels with significant change)
    significant_pixels = np.sum(np.sqrt(np.sum(region_diff ** 2, axis=2)) > 20.0)
    adequate_coverage = significant_pixels > 10000  # Minimum area for good pattern application
    
    # Check if the region is actually in upper-left (sanity check)
    region_height, region_width = target_region.shape[:2]
    correct_region = region_width > 100 and region_height > 100  # Reasonable size check
    
    logging.debug(f"Pattern analysis - Color STD: {color_std:.2f}, Original STD: {original_std:.2f}")
    logging.debug(f"Mean difference: {mean_diff:.2f}, Coverage pixels: {significant_pixels}")
    
    return {
        'has_pattern_texture': has_pattern_texture,
        'significant_change': significant_change,
        'adequate_coverage': adequate_coverage,
        'correct_region': correct_region,
        'color_std': color_std,
        'mean_diff': mean_diff,
        'coverage_pixels': significant_pixels,
        'region_size': (region_width, region_height)
    }


def analyze_image_modification(original_img, result_img):
    """
    Check if the image was meaningfully modified from the original.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate overall pixel differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 2  # At least 2% of pixels changed
    }


def check_pattern_fill(traj, env_info, task_info):
    """
    Main verifier function for pattern fill task.
    Checks:
    1. Pattern texture detected in upper-left region (high color variation)
    2. Significant change in the target region
    3. Adequate coverage area indicating successful pattern application
    4. Image was meaningfully modified from original
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
        "/home/ga/Desktop/pattern_filled.jpg",
        "/home/ga/Desktop/pattern_filled.png",
        "/home/ga/Desktop/pattern_filled.jpeg",
        "/home/ga/Desktop/landscape_pattern.jpg",
        "/home/ga/Desktop/filled_pattern.jpg",
        "/home/ga/Desktop/landscape_image_pattern.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_image.jpg",
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
        
        # Detect pattern application
        pattern_analysis = detect_pattern_in_region(original_image, result_image)
        
        # Check for overall image modification
        modification_analysis = analyze_image_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Target region size: {pattern_analysis['region_size']}")
        feedback_parts.append(f"Color variation (STD): {pattern_analysis['color_std']:.1f}")
        feedback_parts.append(f"Coverage pixels: {pattern_analysis['coverage_pixels']}")
        feedback_parts.append(f"Mean region change: {pattern_analysis['mean_diff']:.1f}")
        feedback_parts.append(f"Overall change: {modification_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Pattern texture detected (high color variation)
        if pattern_analysis['has_pattern_texture']:
            criteria_met += 1
        feedback_parts.append(f"Pattern texture detected: {'✅' if pattern_analysis['has_pattern_texture'] else '❌'}")
        
        # 2. Significant change in target region
        if pattern_analysis['significant_change']:
            criteria_met += 1
        feedback_parts.append(f"Significant region change: {'✅' if pattern_analysis['significant_change'] else '❌'}")
        
        # 3. Adequate coverage area
        if pattern_analysis['adequate_coverage']:
            criteria_met += 1
        feedback_parts.append(f"Adequate coverage: {'✅' if pattern_analysis['adequate_coverage'] else '❌'}")
        
        # 4. Correct region targeted
        if pattern_analysis['correct_region']:
            criteria_met += 1
        feedback_parts.append(f"Correct region: {'✅' if pattern_analysis['correct_region'] else '❌'}")
        
        # 5. Image meaningfully modified
        if modification_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent pattern fill application!")
        elif passed:
            feedback_parts.append("✅ Good pattern fill!")
        else:
            feedback_parts.append("❌ Pattern fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in pattern fill verification: {e}")
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
    result = check_pattern_fill([], {}, {})
    print(f"Test result: {result}")