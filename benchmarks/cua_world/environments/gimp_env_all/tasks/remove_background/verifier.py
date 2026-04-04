#!/usr/bin/env python3
"""
Verifier for GIMP background removal task.
Checks if white background was successfully removed and made transparent.
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
    Analyze transparency in an image with alpha channel.
    Returns statistics about transparency distribution.
    """
    if img.mode not in ['RGBA', 'LA']:
        return None
    
    img_array = np.array(img)
    if len(img_array.shape) < 3:
        return None
        
    alpha_channel = img_array[:, :, -1]  # Get alpha channel (last channel)
    
    total_pixels = alpha_channel.size
    transparent_pixels = np.sum(alpha_channel < 50)      # Mostly transparent
    semi_transparent_pixels = np.sum((alpha_channel >= 50) & (alpha_channel < 200))  # Semi-transparent
    opaque_pixels = np.sum(alpha_channel >= 200)         # Mostly opaque
    
    return {
        'total_pixels': total_pixels,
        'transparent_pixels': transparent_pixels,
        'semi_transparent_pixels': semi_transparent_pixels,
        'opaque_pixels': opaque_pixels,
        'transparent_ratio': transparent_pixels / total_pixels,
        'opaque_ratio': opaque_pixels / total_pixels,
        'alpha_mean': np.mean(alpha_channel),
        'alpha_std': np.std(alpha_channel)
    }


def identify_background_regions(original_img):
    """
    Identify regions in the original image that are likely background (white/light areas).
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    
    orig_array = np.array(original_img)
    
    # Define white/light background regions (high values in all channels)
    background_mask = np.all(orig_array > 240, axis=2)  # Very white areas
    light_background_mask = np.all(orig_array > 220, axis=2) & ~background_mask  # Light areas
    
    return {
        'background_mask': background_mask,
        'light_background_mask': light_background_mask,
        'background_pixels': np.sum(background_mask),
        'light_background_pixels': np.sum(light_background_mask),
        'total_background_pixels': np.sum(background_mask) + np.sum(light_background_mask)
    }


def identify_subject_regions(original_img):
    """
    Identify regions in the original image that are likely subject (non-white areas).
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    
    orig_array = np.array(original_img)
    
    # Define subject regions (areas that are not white/light)
    subject_mask = ~np.all(orig_array > 220, axis=2)  # Non-light areas
    
    return {
        'subject_mask': subject_mask,
        'subject_pixels': np.sum(subject_mask)
    }


def verify_background_removal(original_img, result_img):
    """
    Verify that background was successfully removed from the image.
    """
    # Ensure result image has alpha channel
    if result_img.mode not in ['RGBA', 'LA']:
        return {
            'has_alpha': False,
            'error': 'Result image does not have alpha channel'
        }
    
    # Resize if necessary to match original
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Identify regions in original image
    background_info = identify_background_regions(original_img)
    subject_info = identify_subject_regions(original_img)
    
    # Analyze transparency in result image
    transparency_info = analyze_transparency(result_img)
    
    if transparency_info is None:
        return {
            'has_alpha': False,
            'error': 'Could not analyze transparency'
        }
    
    # Extract alpha channel from result
    result_array = np.array(result_img)
    alpha_channel = result_array[:, :, -1]
    
    # Check transparency in former background regions
    bg_alpha_values = alpha_channel[background_info['background_mask']]
    light_bg_alpha_values = alpha_channel[background_info['light_background_mask']]
    
    # Check opacity in subject regions
    subject_alpha_values = alpha_channel[subject_info['subject_mask']]
    
    # Calculate metrics
    bg_transparent_ratio = np.sum(bg_alpha_values < 50) / len(bg_alpha_values) if len(bg_alpha_values) > 0 else 0
    light_bg_transparent_ratio = np.sum(light_bg_alpha_values < 50) / len(light_bg_alpha_values) if len(light_bg_alpha_values) > 0 else 0
    subject_opaque_ratio = np.sum(subject_alpha_values > 200) / len(subject_alpha_values) if len(subject_alpha_values) > 0 else 0
    
    overall_bg_transparent_ratio = (
        (bg_transparent_ratio * len(bg_alpha_values) + 
         light_bg_transparent_ratio * len(light_bg_alpha_values)) /
        max(len(bg_alpha_values) + len(light_bg_alpha_values), 1)
    )
    
    return {
        'has_alpha': True,
        'background_transparent_ratio': overall_bg_transparent_ratio,
        'subject_opaque_ratio': subject_opaque_ratio,
        'transparency_info': transparency_info,
        'background_pixels': background_info['total_background_pixels'],
        'subject_pixels': subject_info['subject_pixels']
    }


def check_background_removal(traj, env_info, task_info):
    """
    Main verifier function for background removal task.
    Checks:
    1. Result image has alpha channel (RGBA/LA mode)
    2. Background areas (white regions in original) are now transparent
    3. Subject areas (non-white regions) remain opaque
    4. Overall quality of background removal
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
        "/home/ga/Desktop/background_removed.png",
        "/home/ga/Desktop/background_removed.jpg",
        "/home/ga/Desktop/transparent.png",
        "/home/ga/Desktop/product_transparent.png",
        "/home/ga/Desktop/product_image_edited.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/product_image.jpg",
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
        
        # Verify background removal
        verification_result = verify_background_removal(original_image, result_image)
        
        if 'error' in verification_result:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: {verification_result['error']}"
            }
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Has alpha channel: {'✅' if verification_result['has_alpha'] else '❌'}")
        feedback_parts.append(f"Background pixels: {verification_result['background_pixels']}")
        feedback_parts.append(f"Subject pixels: {verification_result['subject_pixels']}")
        feedback_parts.append(f"Background transparent: {verification_result['background_transparent_ratio']:.1%}")
        feedback_parts.append(f"Subject preserved: {verification_result['subject_opaque_ratio']:.1%}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Has alpha channel
        if verification_result['has_alpha']:
            criteria_met += 1
        
        # 2. Background is mostly transparent (≥70%)
        if verification_result['background_transparent_ratio'] >= 0.7:
            criteria_met += 1
            
        # 3. Subject is mostly preserved (≥85% opaque)
        if verification_result['subject_opaque_ratio'] >= 0.85:
            criteria_met += 1
            
        # 4. Overall reasonable transparency distribution
        trans_info = verification_result['transparency_info']
        reasonable_transparency = (
            trans_info['transparent_ratio'] > 0.1 and  # At least 10% transparent
            trans_info['opaque_ratio'] > 0.1 and       # At least 10% opaque
            trans_info['transparent_ratio'] < 0.95     # Not everything transparent
        )
        if reasonable_transparency:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        feedback_parts.append(f"Criteria met: {criteria_met}/{total_criteria}")
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent background removal!")
        elif passed:
            feedback_parts.append("✅ Good background removal!")
        else:
            feedback_parts.append("❌ Background removal needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in background removal verification: {e}")
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
    result = check_background_removal([], {}, {})
    print(f"Test result: {result}")