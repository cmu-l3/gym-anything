#!/usr/bin/env python3
"""
Verifier for GIMP selection stroke task.
Checks if a red elliptical stroke was applied around the flower subject.
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


def detect_red_stroke_pixels(original_img, result_img, tolerance=50):
    """
    Detect new red pixels that weren't in the original image.
    These are likely stroke pixels.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Target red color (#FF0000) with tolerance
    target_red = np.array([255, 0, 0])
    
    # Find red pixels in result image
    red_mask_result = np.all(np.abs(result_array - target_red) <= tolerance, axis=2)
    
    # Find red pixels in original image
    red_mask_original = np.all(np.abs(orig_array - target_red) <= tolerance, axis=2)
    
    # New red pixels = red pixels in result that weren't in original
    new_red_pixels = red_mask_result & ~red_mask_original
    
    return new_red_pixels, np.sum(new_red_pixels)


def analyze_stroke_pattern(new_red_pixels, img_shape):
    """
    Analyze if the detected red pixels form an elliptical pattern in the center.
    """
    if np.sum(new_red_pixels) < 50:  # Minimum stroke pixels
        return {
            'is_elliptical': False,
            'is_centered': False,
            'adequate_size': False,
            'stroke_width_ok': False
        }
    
    # Get coordinates of red pixels
    y_coords, x_coords = np.where(new_red_pixels)
    
    if len(y_coords) == 0:
        return {
            'is_elliptical': False,
            'is_centered': False,
            'adequate_size': False,
            'stroke_width_ok': False
        }
    
    # Check if stroke is centered
    img_center_y, img_center_x = img_shape[0] // 2, img_shape[1] // 2
    stroke_center_y, stroke_center_x = np.mean(y_coords), np.mean(x_coords)
    
    center_distance = np.sqrt((stroke_center_y - img_center_y)**2 + (stroke_center_x - img_center_x)**2)
    max_allowed_offset = min(img_shape[:2]) * 0.15  # 15% of image dimension
    is_centered = center_distance <= max_allowed_offset
    
    # Check if pattern is reasonably elliptical
    coord_range_y = np.max(y_coords) - np.min(y_coords)
    coord_range_x = np.max(x_coords) - np.min(x_coords)
    
    # Elliptical patterns should have reasonable proportions
    if coord_range_y > 0 and coord_range_x > 0:
        aspect_ratio = max(coord_range_y, coord_range_x) / min(coord_range_y, coord_range_x)
        is_elliptical = aspect_ratio <= 3.0  # Not too elongated
    else:
        is_elliptical = False
    
    # Check if stroke size is adequate (should span reasonable portion of image)
    min_expected_span = min(img_shape[:2]) * 0.2  # At least 20% of smaller dimension
    actual_span = max(coord_range_y, coord_range_x)
    adequate_size = actual_span >= min_expected_span
    
    # Estimate stroke width (rough approximation)
    # For a good stroke, we expect the pattern to have some width but not be too thick
    stroke_area = np.sum(new_red_pixels)
    estimated_perimeter = 2 * np.pi * np.sqrt((coord_range_x**2 + coord_range_y**2) / 8)  # Rough ellipse perimeter
    if estimated_perimeter > 0:
        estimated_width = stroke_area / estimated_perimeter
        stroke_width_ok = 4 <= estimated_width <= 20  # Reasonable width range
    else:
        stroke_width_ok = False
    
    return {
        'is_elliptical': is_elliptical,
        'is_centered': is_centered,
        'adequate_size': adequate_size,
        'stroke_width_ok': stroke_width_ok,
        'center_distance': center_distance,
        'aspect_ratio': aspect_ratio if coord_range_y > 0 and coord_range_x > 0 else 0,
        'estimated_width': estimated_width if estimated_perimeter > 0 else 0,
        'stroke_span': actual_span
    }


def check_meaningful_modification(original_img, result_img):
    """Check if the image was meaningfully modified."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # Pixels with >30 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 1  # At least 1% of pixels changed significantly
    }


def check_selection_stroke(traj, env_info, task_info):
    """
    Main verifier function for selection stroke task.
    Checks:
    1. Red stroke pixels were added to the image
    2. Stroke forms an approximately elliptical pattern
    3. Stroke is positioned in the center area
    4. Stroke has appropriate width and size
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
        "/home/ga/Desktop/flower_stroke.jpg",
        "/home/ga/Desktop/flower_stroke.png",
        "/home/ga/Desktop/flower_stroke.jpeg",
        "/home/ga/Desktop/stroke_flower.jpg",
        "/home/ga/Desktop/flower_image_stroked.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_image.jpg",
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
        
        # Detect new red stroke pixels
        new_red_pixels, stroke_pixel_count = detect_red_stroke_pixels(original_image, result_image)
        
        # Analyze stroke pattern
        pattern_analysis = analyze_stroke_pattern(new_red_pixels, result_image.size[::-1])  # PIL size is (width, height)
        
        # Check for meaningful modification
        change_analysis = check_meaningful_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Red stroke pixels detected: {stroke_pixel_count}")
        feedback_parts.append(f"Center distance: {pattern_analysis.get('center_distance', 0):.1f}")
        feedback_parts.append(f"Estimated width: {pattern_analysis.get('estimated_width', 0):.1f}")
        feedback_parts.append(f"Stroke span: {pattern_analysis.get('stroke_span', 0):.1f}")
        feedback_parts.append(f"Change percentage: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Sufficient red stroke pixels detected
        sufficient_stroke = stroke_pixel_count >= 100
        if sufficient_stroke:
            criteria_met += 1
        feedback_parts.append(f"Sufficient red pixels: {'✅' if sufficient_stroke else '❌'}")
        
        # 2. Elliptical pattern detected
        if pattern_analysis['is_elliptical']:
            criteria_met += 1
        feedback_parts.append(f"Elliptical pattern: {'✅' if pattern_analysis['is_elliptical'] else '❌'}")
        
        # 3. Properly centered
        if pattern_analysis['is_centered']:
            criteria_met += 1
        feedback_parts.append(f"Centered positioning: {'✅' if pattern_analysis['is_centered'] else '❌'}")
        
        # 4. Adequate size and width
        if pattern_analysis['adequate_size'] and pattern_analysis['stroke_width_ok']:
            criteria_met += 1
        feedback_parts.append(f"Good size & width: {'✅' if (pattern_analysis['adequate_size'] and pattern_analysis['stroke_width_ok']) else '❌'}")
        
        # 5. Meaningful modification detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) but we'll use 75% threshold
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent selection stroke!")
        elif passed:
            feedback_parts.append("✅ Good selection stroke!")
        else:
            feedback_parts.append("❌ Selection stroke needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in selection stroke verification: {e}")
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
    result = check_selection_stroke([], {}, {})
    print(f"Test result: {result}")