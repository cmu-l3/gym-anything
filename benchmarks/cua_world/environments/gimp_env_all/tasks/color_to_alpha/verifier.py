#!/usr/bin/env python3
"""
Verifier for GIMP color to alpha task.
Checks if white background was successfully removed and transparency was created.
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


def analyze_alpha_channel(img):
    """
    Analyze alpha channel to determine transparency characteristics.
    """
    if img.mode != 'RGBA':
        return {
            'has_alpha_channel': False,
            'transparency_percentage': 0,
            'fully_transparent_pixels': 0,
            'partially_transparent_pixels': 0,
            'opaque_pixels': 0
        }
    
    img_array = np.array(img)
    alpha_channel = img_array[:, :, 3]
    
    # Count transparency levels
    fully_transparent = np.sum(alpha_channel == 0)
    partially_transparent = np.sum((alpha_channel > 0) & (alpha_channel < 255))
    fully_opaque = np.sum(alpha_channel == 255)
    
    total_pixels = alpha_channel.size
    transparency_percentage = (fully_transparent + partially_transparent) / total_pixels * 100
    
    return {
        'has_alpha_channel': True,
        'transparency_percentage': transparency_percentage,
        'fully_transparent_pixels': fully_transparent,
        'partially_transparent_pixels': partially_transparent,
        'opaque_pixels': fully_opaque,
        'total_pixels': total_pixels
    }


def analyze_white_pixel_reduction(original_img, result_img):
    """
    Analyze reduction in white pixels between original and result images.
    """
    # Convert to RGB for analysis
    if original_img.mode != 'RGB':
        original_rgb = original_img.convert('RGB')
    else:
        original_rgb = original_img
    
    if result_img.mode == 'RGBA':
        # For RGBA, we need to composite against white to see visible colors
        background = Image.new('RGB', result_img.size, (255, 255, 255))
        result_rgb = Image.alpha_composite(background.convert('RGBA'), result_img).convert('RGB')
    elif result_img.mode != 'RGB':
        result_rgb = result_img.convert('RGB')
    else:
        result_rgb = result_img
    
    # Resize result to match original if needed
    if original_rgb.size != result_rgb.size:
        result_rgb = result_rgb.resize(original_rgb.size)
    
    orig_array = np.array(original_rgb)
    result_array = np.array(result_rgb)
    
    # Define white pixel threshold (pixels with R,G,B all above 240)
    white_threshold = 240
    
    # Count white pixels in original
    orig_white_mask = np.all(orig_array >= white_threshold, axis=2)
    orig_white_pixels = np.sum(orig_white_mask)
    
    # Count white pixels in result
    result_white_mask = np.all(result_array >= white_threshold, axis=2)
    result_white_pixels = np.sum(result_white_mask)
    
    # Calculate reduction
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    orig_white_percentage = (orig_white_pixels / total_pixels) * 100
    result_white_percentage = (result_white_pixels / total_pixels) * 100
    white_reduction_percentage = orig_white_percentage - result_white_percentage
    
    return {
        'original_white_percentage': orig_white_percentage,
        'result_white_percentage': result_white_percentage,
        'white_reduction_percentage': white_reduction_percentage,
        'original_white_pixels': orig_white_pixels,
        'result_white_pixels': result_white_pixels
    }


def check_meaningful_modification(original_img, result_img):
    """
    Check if the image was meaningfully modified.
    """
    # Resize if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert both to RGBA for comparison
    orig_rgba = original_img.convert('RGBA')
    result_rgba = result_img.convert('RGBA')
    
    orig_array = np.array(orig_rgba)
    result_array = np.array(result_rgba)
    
    # Calculate pixel differences
    pixel_differences = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_difference = np.mean(pixel_differences)
    
    # Count significantly changed pixels (>30 intensity units change)
    significant_changes = np.sum(np.sqrt(np.sum(pixel_differences ** 2, axis=2)) > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_pixel_difference': mean_difference,
        'changed_pixels_percentage': change_percentage,
        'meaningfully_modified': change_percentage > 3  # At least 3% of pixels changed
    }


def check_color_to_alpha(traj, env_info, task_info):
    """
    Main verifier function for color to alpha task.
    Checks:
    1. Alpha channel is present in the result image
    2. Significant transparency was created (at least 15%)
    3. White pixels were substantially reduced (at least 30% reduction)
    4. Image was exported in PNG format (transparency support)
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
        "/home/ga/Desktop/transparent_logo.png",
        "/home/ga/Desktop/transparent_logo.PNG",
        "/home/ga/Desktop/logo_transparent.png",
        "/home/ga/Desktop/logo_white_bg_transparent.png",
        "/home/ga/Desktop/logo_alpha.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/logo_white_bg.png",
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
        
        # Analyze alpha channel
        alpha_analysis = analyze_alpha_channel(result_image)
        
        # Analyze white pixel reduction
        white_analysis = analyze_white_pixel_reduction(original_image, result_image)
        
        # Check for meaningful modification
        modification_analysis = check_meaningful_modification(original_image, result_image)
        
        # Check if result is PNG format (supports transparency)
        result_path = Path(file_info["result_container_path"])
        is_png_format = result_path.suffix.lower() == '.png'
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Result format: {result_path.suffix}")
        feedback_parts.append(f"Has alpha channel: {'✅' if alpha_analysis['has_alpha_channel'] else '❌'}")
        feedback_parts.append(f"Transparency: {alpha_analysis['transparency_percentage']:.1f}%")
        feedback_parts.append(f"White reduction: {white_analysis['white_reduction_percentage']:.1f}%")
        feedback_parts.append(f"PNG format: {'✅' if is_png_format else '❌'}")
        feedback_parts.append(f"Modified: {'✅' if modification_analysis['meaningfully_modified'] else '❌'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Alpha channel present
        if alpha_analysis['has_alpha_channel']:
            criteria_met += 1
        
        # 2. Significant transparency created (at least 15%)
        significant_transparency = alpha_analysis['transparency_percentage'] >= 15.0
        if significant_transparency:
            criteria_met += 1
        feedback_parts.append(f"Significant transparency (≥15%): {'✅' if significant_transparency else '❌'}")
        
        # 3. White pixels substantially reduced (at least 30% reduction)
        substantial_white_reduction = white_analysis['white_reduction_percentage'] >= 30.0
        if substantial_white_reduction:
            criteria_met += 1
        feedback_parts.append(f"Substantial white reduction (≥30%): {'✅' if substantial_white_reduction else '❌'}")
        
        # 4. Proper PNG format for transparency
        if is_png_format:
            criteria_met += 1
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect background removal with transparency!")
        elif passed:
            feedback_parts.append("✅ Good background removal with transparency!")
        else:
            feedback_parts.append("❌ Background removal needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color to alpha verification: {e}")
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
    result = check_color_to_alpha([], {}, {})
    print(f"Test result: {result}")