#!/usr/bin/env python3
"""
Verifier for GIMP partial erasure task.
Checks if alpha channel was added and eraser tool was used to create transparency.
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
    Analyze alpha channel to detect and quantify transparency.
    Returns detailed statistics about transparency in the image.
    """
    # Check if image has alpha channel
    if img.mode not in ('RGBA', 'LA'):
        return {
            'has_alpha': False,
            'transparent_percentage': 0,
            'fully_transparent_percentage': 0,
            'center_transparent_percentage': 0,
            'mean_alpha': 255,
            'alpha_std': 0
        }
    
    # Extract alpha channel
    img_array = np.array(img)
    if len(img_array.shape) == 3:
        alpha_channel = img_array[:, :, -1]  # Last channel is alpha
    else:
        alpha_channel = img_array  # Grayscale with alpha
    
    total_pixels = alpha_channel.size
    
    # Count transparent pixels
    fully_transparent = np.sum(alpha_channel == 0)
    partially_transparent = np.sum((alpha_channel > 0) & (alpha_channel < 255))
    any_transparent = np.sum(alpha_channel < 255)
    
    # Calculate percentages
    fully_transparent_pct = (fully_transparent / total_pixels) * 100
    partially_transparent_pct = (partially_transparent / total_pixels) * 100
    total_transparent_pct = (any_transparent / total_pixels) * 100
    
    # Analyze center region transparency (where erasure is expected)
    center_y, center_x = alpha_channel.shape[0] // 2, alpha_channel.shape[1] // 2
    radius = min(center_y, center_x) // 2
    y_grid, x_grid = np.ogrid[:alpha_channel.shape[0], :alpha_channel.shape[1]]
    center_mask = ((y_grid - center_y)**2 + (x_grid - center_x)**2) <= radius**2
    
    center_transparent_pct = 0
    if np.sum(center_mask) > 0:
        center_transparent_pct = (np.sum(alpha_channel[center_mask] < 255) / 
                                  np.sum(center_mask)) * 100
    
    return {
        'has_alpha': True,
        'total_transparent_percentage': total_transparent_pct,
        'fully_transparent_percentage': fully_transparent_pct,
        'partially_transparent_percentage': partially_transparent_pct,
        'center_transparent_percentage': center_transparent_pct,
        'mean_alpha': np.mean(alpha_channel),
        'alpha_std': np.std(alpha_channel)
    }


def detect_meaningful_erasure(original_img, result_img):
    """
    Detect if meaningful erasure occurred by comparing images.
    """
    # Convert original to RGBA for comparison
    if original_img.mode != 'RGBA':
        # Add fully opaque alpha channel to original
        original_rgba = original_img.convert('RGBA')
    else:
        original_rgba = original_img
    
    if result_img.mode != 'RGBA':
        result_rgba = result_img.convert('RGBA')
    else:
        result_rgba = result_img
    
    # Ensure same size
    if original_rgba.size != result_rgba.size:
        result_rgba = result_rgba.resize(original_rgba.size)
    
    # Compare alpha channels
    orig_array = np.array(original_rgba)
    result_array = np.array(result_rgba)
    
    orig_alpha = orig_array[:, :, 3]
    result_alpha = result_array[:, :, 3]
    
    # Calculate difference in alpha channel
    alpha_diff = np.abs(orig_alpha.astype(np.float32) - result_alpha.astype(np.float32))
    significant_alpha_changes = np.sum(alpha_diff > 50)  # Pixels with significant alpha change
    total_pixels = orig_alpha.size
    
    alpha_change_percentage = (significant_alpha_changes / total_pixels) * 100
    
    return {
        'alpha_change_percentage': alpha_change_percentage,
        'meaningful_erasure': alpha_change_percentage > 5  # At least 5% of pixels changed alpha
    }


def check_partial_erase(traj, env_info, task_info):
    """
    Main verifier function for partial erasure task.
    Checks:
    1. Image has alpha channel (transparency support added)
    2. Significant transparency was created (8%+ of image)
    3. Transparency is distributed appropriately 
    4. Exported as PNG to preserve alpha channel
    5. Clear evidence of erasure from original
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
        "/home/ga/Desktop/erased_image.png",
        "/home/ga/Desktop/erased_image.jpg",
        "/home/ga/Desktop/erased_image.jpeg",
        "/home/ga/Desktop/test_image_erased.png",
        "/home/ga/Desktop/transparent_image.png",
        "/home/ga/Desktop/test_edited.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/test_image.jpg",
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
        
        # Analyze transparency in result image
        transparency_stats = analyze_transparency(result_image)
        
        # Detect meaningful erasure by comparing with original
        erasure_analysis = detect_meaningful_erasure(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Result format: {result_image.format}")
        feedback_parts.append(f"Result mode: {result_image.mode}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Check alpha channel presence
        has_alpha = transparency_stats['has_alpha']
        if has_alpha:
            criteria_met += 1
        feedback_parts.append(f"Alpha channel present: {'✅' if has_alpha else '❌'}")
        
        # 2. Check significant transparency (at least 8%)
        sufficient_transparency = transparency_stats['total_transparent_percentage'] >= 8.0
        if sufficient_transparency:
            criteria_met += 1
        feedback_parts.append(f"Sufficient transparency ({transparency_stats['total_transparent_percentage']:.1f}%): {'✅' if sufficient_transparency else '❌'}")
        
        # 3. Check spatial distribution (should be coherent regions)
        good_distribution = (transparency_stats['total_transparent_percentage'] > 0 and 
                           transparency_stats['alpha_std'] > 50)  # Standard deviation indicates variation
        if good_distribution:
            criteria_met += 1
        feedback_parts.append(f"Good spatial distribution: {'✅' if good_distribution else '❌'}")
        
        # 4. Check PNG format (required for transparency)
        is_png = file_info["result_container_path"].endswith('.png')
        if is_png:
            criteria_met += 1
        feedback_parts.append(f"PNG format (preserves transparency): {'✅' if is_png else '❌'}")
        
        # 5. Check meaningful change from original
        meaningful_change = erasure_analysis['meaningful_erasure']
        if meaningful_change:
            criteria_met += 1
        feedback_parts.append(f"Meaningful erasure detected: {'✅' if meaningful_change else '❌'}")
        
        # Additional detailed feedback
        feedback_parts.append(f"Fully transparent: {transparency_stats['fully_transparent_percentage']:.1f}%")
        feedback_parts.append(f"Partially transparent: {transparency_stats['partially_transparent_percentage']:.1f}%")
        feedback_parts.append(f"Center transparency: {transparency_stats['center_transparent_percentage']:.1f}%")
        feedback_parts.append(f"Alpha change: {erasure_analysis['alpha_change_percentage']:.1f}%")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent transparency creation!")
        elif passed:
            feedback_parts.append("✅ Good partial erasure!")
        else:
            feedback_parts.append("❌ Partial erasure needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in partial erasure verification: {e}")
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
    result = check_partial_erase([], {}, {})
    print(f"Test result: {result}")