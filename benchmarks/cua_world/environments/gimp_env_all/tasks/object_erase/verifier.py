#!/usr/bin/env python3
"""
Verifier for GIMP object erase task.
Checks if an object was successfully removed using the eraser tool, creating transparency.
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


def analyze_transparency(img):
    """
    Analyze transparency in an image.
    Returns metrics about transparent areas.
    """
    if img.mode != 'RGBA':
        # If no alpha channel, convert to RGBA to check
        img = img.convert('RGBA')
    
    img_array = np.array(img)
    alpha_channel = img_array[:, :, 3]
    
    total_pixels = alpha_channel.size
    fully_transparent = np.sum(alpha_channel == 0)
    partially_transparent = np.sum((alpha_channel > 0) & (alpha_channel < 255))
    opaque_pixels = np.sum(alpha_channel == 255)
    
    transparency_percentage = (fully_transparent / total_pixels) * 100
    
    return {
        'has_alpha': True,
        'total_pixels': total_pixels,
        'fully_transparent': fully_transparent,
        'partially_transparent': partially_transparent, 
        'opaque_pixels': opaque_pixels,
        'transparency_percentage': transparency_percentage
    }


def analyze_object_removal(original_img, result_img):
    """
    Analyze if an object (particularly red object) was removed.
    """
    # Ensure both images are in RGB for comparison
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    
    # For result image, we need to handle transparency
    if result_img.mode == 'RGBA':
        result_rgb = result_img.convert('RGB')
    else:
        result_rgb = result_img.convert('RGB')
    
    # Resize result to match original if different
    if original_img.size != result_rgb.size:
        result_rgb = result_rgb.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_rgb)
    
    # Define red color ranges (for detecting red object removal)
    red_mask_orig = ((orig_array[:, :, 0] > 150) & 
                     (orig_array[:, :, 1] < 100) & 
                     (orig_array[:, :, 2] < 100))
    
    red_mask_result = ((result_array[:, :, 0] > 150) & 
                       (result_array[:, :, 1] < 100) & 
                       (result_array[:, :, 2] < 100))
    
    red_pixels_orig = np.sum(red_mask_orig)
    red_pixels_result = np.sum(red_mask_result)
    red_reduction = red_pixels_orig - red_pixels_result
    
    # Calculate overall pixel difference
    pixel_diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(pixel_diff)
    significant_changes = np.sum(np.sqrt(np.sum(pixel_diff ** 2, axis=2)) > 30)
    change_percentage = (significant_changes / (orig_array.shape[0] * orig_array.shape[1])) * 100
    
    return {
        'red_pixels_original': red_pixels_orig,
        'red_pixels_result': red_pixels_result,
        'red_reduction': red_reduction,
        'mean_pixel_difference': mean_diff,
        'change_percentage': change_percentage,
        'significantly_changed': change_percentage > 1.0  # At least 1% of pixels changed significantly
    }


def check_surrounding_preservation(original_img, result_img, transparency_analysis):
    """
    Check if areas that weren't erased remain largely unchanged.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    
    # For result, we need to mask out transparent areas
    if result_img.mode == 'RGBA':
        result_array = np.array(result_img)
        alpha = result_array[:, :, 3]
        # Only compare areas that are not fully transparent
        non_transparent_mask = alpha > 0
        
        if np.sum(non_transparent_mask) > 0:
            result_rgb = result_array[:, :, :3]  # Get RGB channels
            
            # Calculate difference only in non-transparent areas
            diff = np.abs(orig_array.astype(np.float32) - result_rgb.astype(np.float32))
            masked_diff = diff[non_transparent_mask]
            
            if len(masked_diff) > 0:
                preservation_score = 1 - (np.mean(masked_diff) / 255)
                return max(0, preservation_score)  # Ensure non-negative
    
    # Fallback: compare RGB versions
    result_rgb = result_img.convert('RGB')
    result_array = np.array(result_rgb)
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    preservation_score = 1 - (np.mean(diff) / 255)
    
    return max(0, preservation_score)


def check_object_erase(traj, env_info, task_info):
    """
    Main verifier function for object erase task.
    Checks:
    1. Transparency was created (alpha channel with transparent pixels)
    2. Object was removed (reduction in target colors)
    3. Surrounding areas were preserved
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
        "/home/ga/Desktop/object_removed.png",
        "/home/ga/Desktop/object_removed.jpg",
        "/home/ga/Desktop/erased_object.png",
        "/home/ga/Desktop/test_object_image_erased.png",
        "/home/ga/Desktop/removed.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/test_object_image.png",
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
        logging.debug(f"Original mode: {original_image.mode}, Result mode: {result_image.mode}")
        
        # Analyze transparency
        transparency_analysis = analyze_transparency(result_image)
        
        # Analyze object removal
        removal_analysis = analyze_object_removal(original_image, result_image)
        
        # Check surrounding area preservation
        preservation_score = check_surrounding_preservation(original_image, result_image, transparency_analysis)
        
        # Check if images are different
        images_different = removal_analysis['significantly_changed']
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Result format: {result_image.mode}")
        feedback_parts.append(f"Transparent pixels: {transparency_analysis['fully_transparent']}")
        feedback_parts.append(f"Transparency %: {transparency_analysis['transparency_percentage']:.1f}%")
        feedback_parts.append(f"Red pixels removed: {removal_analysis['red_reduction']}")
        feedback_parts.append(f"Pixels changed: {removal_analysis['change_percentage']:.1f}%")
        feedback_parts.append(f"Preservation score: {preservation_score:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Transparency created (at least 100 transparent pixels)
        transparency_created = transparency_analysis['fully_transparent'] >= 100
        if transparency_created:
            criteria_met += 1
        feedback_parts.append(f"Transparency created: {'✅' if transparency_created else '❌'}")
        
        # 2. Object removed (red reduction or significant changes)
        object_removed = (removal_analysis['red_reduction'] > 50 or 
                         removal_analysis['change_percentage'] > 2.0)
        if object_removed:
            criteria_met += 1
        feedback_parts.append(f"Object removed: {'✅' if object_removed else '❌'}")
        
        # 3. Appropriate location (transparency should be in reasonable area)
        appropriate_location = 0.5 <= transparency_analysis['transparency_percentage'] <= 25.0
        if appropriate_location:
            criteria_met += 1
        feedback_parts.append(f"Appropriate removal area: {'✅' if appropriate_location else '❌'}")
        
        # 4. Surrounding preserved (at least 85% similarity in non-transparent areas)
        surrounding_preserved = preservation_score >= 0.85
        if surrounding_preserved:
            criteria_met += 1
        feedback_parts.append(f"Surrounding preserved: {'✅' if surrounding_preserved else '❌'}")
        
        # 5. Image modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect object removal with transparency!")
        elif passed:
            feedback_parts.append("✅ Good object removal!")
        else:
            feedback_parts.append("❌ Object removal needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in object erase verification: {e}")
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
    result = check_object_erase([], {}, {})
    print(f"Test result: {result}")