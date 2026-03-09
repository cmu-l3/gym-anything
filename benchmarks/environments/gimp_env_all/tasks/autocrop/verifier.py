#!/usr/bin/env python3
"""
Verifier for GIMP autocrop task.
Checks if uniform borders were automatically removed from the image.
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


def check_dimension_reduction(original_img, result_img):
    """Check if image dimensions were reduced appropriately."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Check if dimensions decreased
    width_decreased = orig_w > result_w
    height_decreased = orig_h > result_h
    dimensions_reduced = width_decreased or height_decreased
    
    # Calculate area reduction
    orig_area = orig_w * orig_h
    result_area = result_w * result_h
    area_reduction = 1 - (result_area / orig_area)
    
    # Check if reduction is meaningful but not excessive
    meaningful_reduction = area_reduction >= 0.05  # At least 5% reduction
    not_over_cropped = area_reduction <= 0.50  # Less than 50% reduction
    
    return {
        'dimensions_reduced': dimensions_reduced,
        'area_reduction': area_reduction,
        'meaningful_reduction': meaningful_reduction,
        'not_over_cropped': not_over_cropped,
        'original_size': (orig_w, orig_h),
        'result_size': (result_w, result_h)
    }


def analyze_border_uniformity(img, border_thickness=20):
    """Analyze if the image has uniform borders."""
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    
    # Extract border regions
    top_border = img_array[:min(border_thickness, height//4), :, :]
    bottom_border = img_array[max(-border_thickness, -height//4):, :, :]
    left_border = img_array[:, :min(border_thickness, width//4), :]
    right_border = img_array[:, max(-border_thickness, -width//4):, :]
    
    borders_info = []
    
    for border_name, border in [('top', top_border), ('bottom', bottom_border), 
                               ('left', left_border), ('right', right_border)]:
        if border.size == 0:
            continue
            
        # Calculate standard deviation for each color channel
        std_r = np.std(border[:, :, 0])
        std_g = np.std(border[:, :, 1]) 
        std_b = np.std(border[:, :, 2])
        avg_std = (std_r + std_g + std_b) / 3
        
        # Low standard deviation indicates uniform color
        is_uniform = avg_std < 15  # Threshold for uniformity
        
        borders_info.append({
            'border': border_name,
            'std_dev': avg_std,
            'is_uniform': is_uniform,
            'mean_color': np.mean(border, axis=(0, 1))
        })
    
    # Check if any borders were uniform (indicating autocrop was needed)
    uniform_borders = [b for b in borders_info if b['is_uniform']]
    had_uniform_borders = len(uniform_borders) > 0
    
    return {
        'borders_info': borders_info,
        'uniform_borders': uniform_borders,
        'had_uniform_borders': had_uniform_borders
    }


def verify_content_preservation(original_img, result_img):
    """Verify that main content was preserved during autocrop."""
    # Convert to grayscale for analysis
    orig_gray = original_img.convert('L')
    result_gray = result_img.convert('L')
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Analyze center region detail preservation
    orig_h, orig_w = orig_array.shape
    result_h, result_w = result_array.shape
    
    # Define center regions (middle 60% of each image)
    orig_center_y1, orig_center_y2 = int(orig_h * 0.2), int(orig_h * 0.8)
    orig_center_x1, orig_center_x2 = int(orig_w * 0.2), int(orig_w * 0.8)
    orig_center = orig_array[orig_center_y1:orig_center_y2, orig_center_x1:orig_center_x2]
    
    result_center_y1, result_center_y2 = int(result_h * 0.2), int(result_h * 0.8)
    result_center_x1, result_center_x2 = int(result_w * 0.2), int(result_w * 0.8)
    result_center = result_array[result_center_y1:result_center_y2, result_center_x1:result_center_x2]
    
    # Calculate detail level (standard deviation) in center regions
    orig_center_detail = np.std(orig_center) if orig_center.size > 0 else 0
    result_center_detail = np.std(result_center) if result_center.size > 0 else 0
    
    # Content should be preserved (similar detail level)
    detail_ratio = result_center_detail / max(orig_center_detail, 1)
    content_preserved = detail_ratio >= 0.7  # At least 70% of detail preserved
    
    return {
        'orig_center_detail': orig_center_detail,
        'result_center_detail': result_center_detail,
        'detail_ratio': detail_ratio,
        'content_preserved': content_preserved
    }


def check_autocrop(traj, env_info, task_info):
    """
    Main verifier function for autocrop task.
    Checks:
    1. Image dimensions were reduced (borders removed)
    2. Original image had uniform borders to remove
    3. Content was preserved in the center
    4. Reduction was meaningful but not excessive
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
        "/home/ga/Desktop/autocropped_image.png",
        "/home/ga/Desktop/autocropped_image.jpg", 
        "/home/ga/Desktop/autocropped_image.jpeg",
        "/home/ga/Desktop/bordered_image_autocropped.png",
        "/home/ga/Desktop/cropped.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/bordered_image.png",
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
        
        # Check dimension reduction
        dimension_analysis = check_dimension_reduction(original_image, result_image)
        
        # Analyze original image for uniform borders
        border_analysis = analyze_border_uniformity(original_image)
        
        # Verify content preservation
        content_analysis = verify_content_preservation(original_image, result_image)
        
        # Check if image was modified
        images_different = (original_image.size != result_image.size or 
                          not np.array_equal(np.array(original_image.convert('RGB')), 
                                           np.array(result_image.convert('RGB'))))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {dimension_analysis['original_size']}")
        feedback_parts.append(f"Result size: {dimension_analysis['result_size']}")
        feedback_parts.append(f"Area reduction: {dimension_analysis['area_reduction']:.1%}")
        feedback_parts.append(f"Dimensions reduced: {'✅' if dimension_analysis['dimensions_reduced'] else '❌'}")
        feedback_parts.append(f"Meaningful reduction: {'✅' if dimension_analysis['meaningful_reduction'] else '❌'}")
        feedback_parts.append(f"Not over-cropped: {'✅' if dimension_analysis['not_over_cropped'] else '❌'}")
        feedback_parts.append(f"Had uniform borders: {'✅' if border_analysis['had_uniform_borders'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_analysis['content_preserved'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        if border_analysis['uniform_borders']:
            uniform_borders_str = ', '.join([b['border'] for b in border_analysis['uniform_borders']])
            feedback_parts.append(f"Uniform borders detected: {uniform_borders_str}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimension_analysis['dimensions_reduced']:
            criteria_met += 1
        if border_analysis['had_uniform_borders']:
            criteria_met += 1
        if content_analysis['content_preserved']:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Additional checks for quality
        quality_bonus = 0
        if dimension_analysis['meaningful_reduction'] and dimension_analysis['not_over_cropped']:
            quality_bonus = 1
        
        # Score based on criteria met plus quality bonus
        base_score = int((criteria_met / total_criteria) * 75)
        quality_score = quality_bonus * 25
        score = min(base_score + quality_score, 100)
        
        passed = score >= 75  # Need at least 3/4 criteria plus good quality
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect autocrop operation!")
        elif passed:
            feedback_parts.append("✅ Good autocrop operation!")
        else:
            feedback_parts.append("❌ Autocrop needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in autocrop verification: {e}")
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
    result = check_autocrop([], {}, {})
    print(f"Test result: {result}")