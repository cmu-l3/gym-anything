#!/usr/bin/env python3
"""
Verifier for GIMP eraser transparency task.
Checks if transparency was successfully created using the eraser tool.
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


def analyze_transparency(img_path):
    """
    Analyze transparency in an image by examining the alpha channel.
    Returns transparency statistics and validation flags.
    """
    try:
        img = Image.open(img_path)
        
        # Check if image has alpha channel
        if img.mode not in ('RGBA', 'LA', 'PA'):
            return {
                'has_alpha': False,
                'transparency_percentage': 0,
                'fully_transparent_pixels': 0,
                'partially_transparent_pixels': 0,
                'total_pixels': 0,
                'error': 'No alpha channel in image'
            }
        
        # Convert to RGBA for consistent processing
        img_rgba = img.convert('RGBA')
        img_array = np.array(img_rgba)
        
        # Extract alpha channel
        alpha_channel = img_array[:, :, 3]
        total_pixels = alpha_channel.size
        
        # Count different types of transparency
        fully_transparent = np.sum(alpha_channel == 0)
        partially_transparent = np.sum((alpha_channel > 0) & (alpha_channel < 255))
        opaque_pixels = np.sum(alpha_channel == 255)
        
        # Calculate total transparent pixels
        total_transparent = fully_transparent + partially_transparent
        transparency_percentage = (total_transparent / total_pixels) * 100
        
        return {
            'has_alpha': True,
            'transparency_percentage': transparency_percentage,
            'fully_transparent_pixels': fully_transparent,
            'partially_transparent_pixels': partially_transparent,
            'opaque_pixels': opaque_pixels,
            'total_pixels': total_pixels,
            'error': None
        }
        
    except Exception as e:
        logging.error(f"Error analyzing transparency: {e}")
        return {
            'has_alpha': False,
            'transparency_percentage': 0,
            'error': str(e)
        }


def compare_transparency_change(original_path, result_path):
    """
    Compare transparency between original and result images.
    Returns metrics about the change in transparency.
    """
    try:
        # Analyze both images
        original_stats = analyze_transparency(original_path)
        result_stats = analyze_transparency(result_path)
        
        if original_stats['error'] or result_stats['error']:
            return {
                'transparency_increase': 0,
                'meaningful_change': False,
                'error': original_stats.get('error') or result_stats.get('error')
            }
        
        # Calculate change in transparency
        transparency_increase = (result_stats['transparency_percentage'] - 
                               original_stats['transparency_percentage'])
        
        # Check if change is meaningful (at least 2 percentage points)
        meaningful_change = transparency_increase >= 2.0
        
        return {
            'original_transparency': original_stats['transparency_percentage'],
            'result_transparency': result_stats['transparency_percentage'],
            'transparency_increase': transparency_increase,
            'meaningful_change': meaningful_change,
            'error': None
        }
        
    except Exception as e:
        logging.error(f"Error comparing transparency: {e}")
        return {
            'transparency_increase': 0,
            'meaningful_change': False,
            'error': str(e)
        }


def check_eraser_transparency(traj, env_info, task_info):
    """
    Main verifier function for eraser transparency task.
    Checks:
    1. Image has alpha channel with transparency
    2. Significant transparency was created (>2% of image)
    3. Content was preserved (not over-erased)
    4. Image was exported in proper format (PNG)
    5. Meaningful change from original
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
        "/home/ga/Desktop/erased_image.jpg",  # In case exported as JPEG by mistake
        "/home/ga/Desktop/eraseme_image_edited.png",
        "/home/ga/Desktop/eraseme_erased.png",
        "/home/ga/Desktop/transparent_image.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/eraseme_image.png",
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
        # Analyze result image transparency
        result_stats = analyze_transparency(file_info["result_path"])
        
        # Compare with original image
        change_stats = compare_transparency_change(
            file_info["original_path"], 
            file_info["result_path"]
        )
        
        logging.debug(f"Found result image at: {file_info['result_container_path']}")
        
        feedback_parts = []
        feedback_parts.append(f"Result format: {Path(file_info['result_container_path']).suffix}")
        feedback_parts.append(f"Has alpha channel: {'✅' if result_stats['has_alpha'] else '❌'}")
        feedback_parts.append(f"Transparency: {result_stats['transparency_percentage']:.1f}%")
        feedback_parts.append(f"Transparent pixels: {result_stats.get('fully_transparent_pixels', 0) + result_stats.get('partially_transparent_pixels', 0)}")
        feedback_parts.append(f"Original transparency: {change_stats.get('original_transparency', 0):.1f}%")
        feedback_parts.append(f"Transparency increase: {change_stats.get('transparency_increase', 0):.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Has alpha channel and transparency
        has_transparency = result_stats['has_alpha'] and result_stats['transparency_percentage'] > 2.0
        if has_transparency:
            criteria_met += 1
        feedback_parts.append(f"Substantial transparency (>2%): {'✅' if has_transparency else '❌'}")
        
        # 2. Meaningful change from original
        if change_stats.get('meaningful_change', False):
            criteria_met += 1
        feedback_parts.append(f"Meaningful change from original: {'✅' if change_stats.get('meaningful_change', False) else '❌'}")
        
        # 3. Content preserved (not over-erased)
        content_preserved = result_stats['transparency_percentage'] < 80.0
        if content_preserved:
            criteria_met += 1
        feedback_parts.append(f"Content preserved (<80% erased): {'✅' if content_preserved else '❌'}")
        
        # 4. Reasonable amount erased (not too little, not too much)
        reasonable_amount = 2.0 <= result_stats['transparency_percentage'] <= 60.0
        if reasonable_amount:
            criteria_met += 1
        feedback_parts.append(f"Reasonable erasure amount: {'✅' if reasonable_amount else '❌'}")
        
        # 5. Proper format (PNG to preserve transparency)
        is_png = file_info["result_container_path"].endswith('.png')
        if is_png:
            criteria_met += 1
        feedback_parts.append(f"PNG format (preserves transparency): {'✅' if is_png else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        # Determine feedback message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent transparency creation with eraser tool!")
        elif passed:
            feedback_parts.append("✅ Good transparency creation!")
        else:
            feedback_parts.append("❌ Eraser transparency task needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in eraser transparency verification: {e}")
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
    result = check_eraser_transparency([], {}, {})
    print(f"Test result: {result}")