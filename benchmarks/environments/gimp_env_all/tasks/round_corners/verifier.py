#!/usr/bin/env python3
"""
Verifier for GIMP round corners task.
Checks if rounded corners effect was successfully applied using transparency analysis.
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


def analyze_corner_transparency(img, corner_size_ratio=0.15):
    """
    Analyze transparency in corner regions to detect rounded corners.
    Returns statistics about transparency in each corner.
    """
    if img.mode != 'RGBA':
        # Try to convert, but if no alpha channel exists, this indicates no rounding was applied
        if 'transparency' in img.info or img.mode == 'P':
            img = img.convert('RGBA')
        else:
            # No transparency information available
            return {
                'corners_analyzed': 0,
                'transparent_corners': 0,
                'transparency_ratios': [],
                'has_alpha': False
            }
    
    width, height = img.size
    img_array = np.array(img)
    alpha_channel = img_array[:, :, 3]
    
    # Define corner regions (percentage of image dimensions)
    corner_size = int(min(width, height) * corner_size_ratio)
    
    corners = {
        'top_left': alpha_channel[0:corner_size, 0:corner_size],
        'top_right': alpha_channel[0:corner_size, -corner_size:],
        'bottom_left': alpha_channel[-corner_size:, 0:corner_size],
        'bottom_right': alpha_channel[-corner_size:, -corner_size:]
    }
    
    corner_stats = []
    transparent_corners = 0
    
    for corner_name, corner_data in corners.items():
        if corner_data.size == 0:
            continue
            
        # Count pixels with alpha < 255 (transparent/semi-transparent)
        transparent_pixels = np.sum(corner_data < 255)
        total_pixels = corner_data.size
        transparency_ratio = transparent_pixels / total_pixels if total_pixels > 0 else 0
        
        # Get corner pixel alpha (the actual corner pixel)
        if corner_name == 'top_left':
            corner_alpha = corner_data[0, 0]
        elif corner_name == 'top_right':
            corner_alpha = corner_data[0, -1] 
        elif corner_name == 'bottom_left':
            corner_alpha = corner_data[-1, 0]
        else:  # bottom_right
            corner_alpha = corner_data[-1, -1]
        
        corner_stats.append({
            'name': corner_name,
            'transparency_ratio': transparency_ratio,
            'corner_pixel_alpha': corner_alpha,
            'is_rounded': transparency_ratio >= 0.15 and corner_alpha < 128
        })
        
        if transparency_ratio >= 0.15 and corner_alpha < 128:
            transparent_corners += 1
        
        logging.debug(f"{corner_name}: transparency_ratio={transparency_ratio:.3f}, corner_alpha={corner_alpha}")
    
    return {
        'corners_analyzed': len(corner_stats),
        'transparent_corners': transparent_corners,
        'transparency_ratios': [c['transparency_ratio'] for c in corner_stats],
        'corner_stats': corner_stats,
        'has_alpha': True
    }


def check_rounded_corners_quality(original_img, result_img):
    """
    Check the quality of rounded corners implementation.
    """
    # Basic size and format checks
    size_preserved = original_img.size == result_img.size
    
    # Check if image was modified
    if original_img.mode != result_img.mode:
        # Different modes indicate modification (likely alpha channel added)
        images_different = True
    else:
        try:
            orig_array = np.array(original_img)
            result_array = np.array(result_img.convert(original_img.mode))
            images_different = not np.array_equal(orig_array, result_array)
        except:
            images_different = True
    
    # Analyze corner transparency
    corner_analysis = analyze_corner_transparency(result_img)
    
    return {
        'size_preserved': size_preserved,
        'images_different': images_different,
        'has_alpha_channel': corner_analysis['has_alpha'],
        'corners_with_transparency': corner_analysis['transparent_corners'],
        'total_corners_analyzed': corner_analysis['corners_analyzed'],
        'corner_details': corner_analysis.get('corner_stats', [])
    }


def check_round_corners(traj, env_info, task_info):
    """
    Main verifier function for round corners task.
    Checks:
    1. Image has alpha channel (transparency support)
    2. All four corners show appropriate transparency
    3. Corner transparency follows expected rounded pattern
    4. Image dimensions and quality are preserved
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
        "/home/ga/Desktop/rounded_corners.png",
        "/home/ga/Desktop/rounded_corners.jpg", 
        "/home/ga/Desktop/rounded_corners.jpeg",
        "/home/ga/Desktop/corner_image_rounded.png",
        "/home/ga/Desktop/corner_image_edited.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/corner_image.jpg",
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
        
        # Analyze rounded corners quality
        quality_analysis = check_rounded_corners_quality(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original mode: {original_image.mode}")
        feedback_parts.append(f"Result mode: {result_image.mode}")
        feedback_parts.append(f"Has alpha channel: {'✅' if quality_analysis['has_alpha_channel'] else '❌'}")
        feedback_parts.append(f"Corners with transparency: {quality_analysis['corners_with_transparency']}/4")
        feedback_parts.append(f"Image modified: {'✅' if quality_analysis['images_different'] else '❌'}")
        feedback_parts.append(f"Size preserved: {'✅' if quality_analysis['size_preserved'] else '❌'}")
        
        # Add details about each corner
        for corner_detail in quality_analysis['corner_details']:
            feedback_parts.append(f"{corner_detail['name']}: {'✅' if corner_detail['is_rounded'] else '❌'} (transparency: {corner_detail['transparency_ratio']:.2f})")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 6
        
        # 1. Has alpha channel
        if quality_analysis['has_alpha_channel']:
            criteria_met += 1
        
        # 2. All corners have transparency (all 4 corners should be rounded)
        if quality_analysis['corners_with_transparency'] >= 4:
            criteria_met += 1
        elif quality_analysis['corners_with_transparency'] >= 3:
            criteria_met += 0.5  # Partial credit for 3 corners
        
        # 3. Image was modified
        if quality_analysis['images_different']:
            criteria_met += 1
        
        # 4. Size preserved
        if quality_analysis['size_preserved']:
            criteria_met += 1
        
        # 5. Reasonable number of corners analyzed
        if quality_analysis['total_corners_analyzed'] == 4:
            criteria_met += 1
        
        # 6. Quality check - at least 50% of corners properly rounded
        corner_success_rate = quality_analysis['corners_with_transparency'] / max(quality_analysis['total_corners_analyzed'], 1)
        if corner_success_rate >= 0.5:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4.5/6 criteria (75%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rounded corners applied!")
        elif passed:
            feedback_parts.append("✅ Good rounded corners effect!")
        else:
            feedback_parts.append("❌ Rounded corners not properly applied")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in round corners verification: {e}")
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
    result = check_round_corners([], {}, {})
    print(f"Test result: {result}")