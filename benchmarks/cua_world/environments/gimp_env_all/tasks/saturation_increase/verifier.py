#!/usr/bin/env python3
"""
Verifier for GIMP saturation increase task.
Checks if colors in the image were made more vibrant by increasing saturation.
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


def calculate_saturation_metrics(original_img, result_img):
    """
    Calculate saturation increase using HSV color space.
    Returns detailed metrics about the saturation changes.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to HSV color space
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    try:
        orig_hsv = original_img.convert('HSV')
        result_hsv = result_img.convert('HSV')
        
        # Extract saturation channel (index 1 in HSV: H=0, S=1, V=2)
        orig_s = np.array(orig_hsv)[:, :, 1].astype(np.float32)
        result_s = np.array(result_hsv)[:, :, 1].astype(np.float32)
        
        # Calculate statistics
        orig_mean_sat = np.mean(orig_s)
        result_mean_sat = np.mean(result_s)
        absolute_increase = result_mean_sat - orig_mean_sat
        
        # Calculate percentage increase
        if orig_mean_sat > 5:  # Avoid division by very small numbers
            relative_increase = (absolute_increase / orig_mean_sat) * 100
        else:
            relative_increase = 0
        
        # Check for over-saturation (clipping at high values)
        over_saturated_ratio = np.sum(result_s >= 250) / result_s.size
        
        return {
            'original_mean': orig_mean_sat,
            'result_mean': result_mean_sat,
            'absolute_increase': absolute_increase,
            'relative_increase_percent': relative_increase,
            'over_saturation_ratio': over_saturated_ratio,
            'success': True
        }
        
    except Exception as e:
        logging.error(f"Error in HSV conversion: {e}")
        # Fallback: simple RGB analysis if HSV fails
        return calculate_rgb_color_intensity(original_img, result_img)


def calculate_rgb_color_intensity(original_img, result_img):
    """
    Fallback method using RGB color intensity analysis.
    """
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate color intensity as distance from gray
    def color_intensity(img_array):
        # Convert to float for calculations
        img_float = img_array.astype(np.float32)
        
        # Calculate grayscale equivalent
        gray = np.mean(img_float, axis=2, keepdims=True)
        
        # Calculate distance from gray (color intensity)
        intensity = np.sqrt(np.sum((img_float - gray) ** 2, axis=2))
        return np.mean(intensity)
    
    orig_intensity = color_intensity(orig_array)
    result_intensity = color_intensity(result_array)
    
    absolute_increase = result_intensity - orig_intensity
    relative_increase = (absolute_increase / max(orig_intensity, 1)) * 100
    
    return {
        'original_mean': orig_intensity,
        'result_mean': result_intensity,
        'absolute_increase': absolute_increase,
        'relative_increase_percent': relative_increase,
        'over_saturation_ratio': 0.0,  # Cannot detect clipping with this method
        'success': True
    }


def validate_saturation_enhancement(metrics):
    """
    Apply verification criteria to saturation metrics.
    """
    checks = {
        'sufficient_relative_increase': metrics['relative_increase_percent'] >= 15,
        'reasonable_bounds': metrics['relative_increase_percent'] <= 80,
        'no_excessive_clipping': metrics['over_saturation_ratio'] < 0.05,
        'sufficient_absolute_increase': metrics['absolute_increase'] >= 10
    }
    
    passed_count = sum(checks.values())
    score = (passed_count / len(checks)) * 100
    
    return score, checks, metrics


def check_saturation_increase(traj, env_info, task_info):
    """
    Main verifier function for saturation increase task.
    Checks:
    1. Mean saturation increased by at least 15% from original
    2. Saturation increase is between 15% and 80% (not excessive)
    3. Less than 5% of pixels at maximum saturation (avoiding clipping)
    4. Mean saturation absolute increase is at least 10 points (0-255 scale)
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
        "/home/ga/Desktop/vibrant_colors.jpg",
        "/home/ga/Desktop/vibrant_colors.png",
        "/home/ga/Desktop/vibrant_colors.jpeg",
        "/home/ga/Desktop/colorful_landscape_enhanced.jpg",
        "/home/ga/Desktop/colorful_landscape_saturated.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/colorful_landscape.jpg",
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
        
        # Calculate saturation metrics
        saturation_metrics = calculate_saturation_metrics(original_image, result_image)
        
        if not saturation_metrics['success']:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to analyze saturation changes"
            }
        
        # Validate the enhancement
        score, checks, metrics = validate_saturation_enhancement(saturation_metrics)
        
        # Check if image was modified (basic pixel comparison)
        images_different = not np.array_equal(
            np.array(original_image.convert('RGB')), 
            np.array(result_image.convert('RGB'))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original mean saturation: {metrics['original_mean']:.1f}")
        feedback_parts.append(f"Result mean saturation: {metrics['result_mean']:.1f}")
        feedback_parts.append(f"Absolute increase: {metrics['absolute_increase']:.1f}")
        feedback_parts.append(f"Relative increase: {metrics['relative_increase_percent']:.1f}%")
        feedback_parts.append(f"Over-saturation ratio: {metrics['over_saturation_ratio']:.3f}")
        
        # Report individual check results
        feedback_parts.append(f"Sufficient relative increase (≥15%): {'✅' if checks['sufficient_relative_increase'] else '❌'}")
        feedback_parts.append(f"Reasonable bounds (≤80%): {'✅' if checks['reasonable_bounds'] else '❌'}")
        feedback_parts.append(f"No excessive clipping (<5%): {'✅' if checks['no_excessive_clipping'] else '❌'}")
        feedback_parts.append(f"Sufficient absolute increase (≥10): {'✅' if checks['sufficient_absolute_increase'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Determine success
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent saturation enhancement!")
        elif passed:
            feedback_parts.append("✅ Good saturation enhancement!")
        else:
            feedback_parts.append("❌ Saturation enhancement needs improvement")
            
        return {
            "passed": passed,
            "score": int(score),
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in saturation increase verification: {e}")
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
    result = check_saturation_increase([], {}, {})
    print(f"Test result: {result}")