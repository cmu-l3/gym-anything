#!/usr/bin/env python3
"""
Verifier for GIMP brightness adjustment task.
Checks if image brightness was increased while preserving quality.
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


def calculate_luminance(image):
    """
    Calculate average luminance using ITU-R BT.709 standard formula.
    Returns the mean luminance value of the image.
    """
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    img_array = np.array(image)
    
    # ITU-R BT.709 luminance formula
    luminance = (0.299 * img_array[:,:,0] + 
                0.587 * img_array[:,:,1] + 
                0.114 * img_array[:,:,2])
    
    return np.mean(luminance)


def detect_highlight_clipping(image, threshold=250):
    """
    Detect percentage of pixels with blown highlights.
    Returns percentage of pixels where any RGB channel >= threshold.
    """
    if image.mode != 'RGB':
        image = image.convert('RGB')
    
    img_array = np.array(image)
    
    # Count pixels where any channel is at or above threshold
    clipped_pixels = np.any(img_array >= threshold, axis=2)
    clipping_percentage = np.mean(clipped_pixels) * 100
    
    return clipping_percentage


def analyze_brightness_change(original_img, result_img):
    """
    Analyze brightness changes between original and result images.
    Returns comprehensive brightness analysis metrics.
    """
    # Calculate luminance for both images
    orig_luminance = calculate_luminance(original_img)
    result_luminance = calculate_luminance(result_img)
    
    # Calculate brightness increase
    luminance_delta = result_luminance - orig_luminance
    if orig_luminance > 0:
        brightness_increase_percent = (luminance_delta / orig_luminance) * 100
    else:
        brightness_increase_percent = 0
    
    # Detect highlight clipping in result
    clipping_percent = detect_highlight_clipping(result_img)
    
    # Analyze shadow detail improvement
    orig_dark_pixels = np.sum(np.array(original_img.convert('L')) < 50)
    result_dark_pixels = np.sum(np.array(result_img.convert('L')) < 50)
    total_pixels = original_img.size[0] * original_img.size[1]
    
    shadow_improvement = ((orig_dark_pixels - result_dark_pixels) / total_pixels) * 100
    
    return {
        'original_luminance': orig_luminance,
        'result_luminance': result_luminance,
        'luminance_delta': luminance_delta,
        'brightness_increase_percent': brightness_increase_percent,
        'highlight_clipping_percent': clipping_percent,
        'shadow_improvement_percent': shadow_improvement
    }


def check_meaningful_change(original_img, result_img):
    """
    Check if the images show meaningful brightness adjustment changes.
    """
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of meaningfully changed pixels
    pixel_changes = np.sqrt(np.sum(diff ** 2, axis=2))
    significant_changes = np.sum(pixel_changes > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 10  # At least 10% of pixels changed
    }


def check_brightness_adjustment(traj, env_info, task_info):
    """
    Main verifier function for brightness adjustment task.
    Checks:
    1. Significant brightness increase (at least 10%)
    2. Quality preserved (less than 5% highlight clipping)
    3. Meaningful change in image pixels
    4. Natural-looking result
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
        "/home/ga/Desktop/brightened_portrait.jpg",
        "/home/ga/Desktop/brightened_portrait.png",
        "/home/ga/Desktop/brightened_portrait.jpeg",
        "/home/ga/Desktop/bright_portrait.jpg",
        "/home/ga/Desktop/portrait_bright.jpg",
        "/home/ga/Desktop/dark_portrait_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/dark_portrait.jpg",
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
        
        # Analyze brightness changes
        brightness_analysis = analyze_brightness_change(original_image, result_image)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original luminance: {brightness_analysis['original_luminance']:.1f}")
        feedback_parts.append(f"Result luminance: {brightness_analysis['result_luminance']:.1f}")
        feedback_parts.append(f"Luminance delta: +{brightness_analysis['luminance_delta']:.1f}")
        feedback_parts.append(f"Brightness increase: {brightness_analysis['brightness_increase_percent']:.1f}%")
        feedback_parts.append(f"Highlight clipping: {brightness_analysis['highlight_clipping_percent']:.1f}%")
        feedback_parts.append(f"Shadow improvement: {brightness_analysis['shadow_improvement_percent']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant brightness increase (at least 10%)
        brightness_increased = brightness_analysis['brightness_increase_percent'] >= 10.0
        if brightness_increased:
            criteria_met += 1
        feedback_parts.append(f"Brightness increased significantly: {'✅' if brightness_increased else '❌'}")
        
        # 2. Quality preserved (less than 5% highlight clipping)
        quality_preserved = brightness_analysis['highlight_clipping_percent'] < 5.0
        if quality_preserved:
            criteria_met += 1
        feedback_parts.append(f"Quality preserved: {'✅' if quality_preserved else '❌'}")
        
        # 3. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image meaningfully modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # 4. Natural result (brightness increase within reasonable bounds)
        natural_result = 10.0 <= brightness_analysis['brightness_increase_percent'] <= 100.0
        if natural_result:
            criteria_met += 1
        feedback_parts.append(f"Natural brightness adjustment: {'✅' if natural_result else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent brightness adjustment!")
        elif passed:
            feedback_parts.append("✅ Good brightness improvement!")
        else:
            feedback_parts.append("❌ Brightness adjustment needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in brightness adjustment verification: {e}")
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
    result = check_brightness_adjustment([], {}, {})
    print(f"Test result: {result}")