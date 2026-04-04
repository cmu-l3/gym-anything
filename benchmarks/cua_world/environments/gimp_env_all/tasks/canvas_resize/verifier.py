#!/usr/bin/env python3
"""
Verifier for GIMP canvas resize task.
Checks if canvas was expanded to 1000x800 with original content preserved and centered.
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


def check_canvas_dimensions(img, target_width=1000, target_height=800, tolerance=5):
    """Check if image has target canvas dimensions within tolerance."""
    width, height = img.size
    
    width_ok = abs(width - target_width) <= tolerance
    height_ok = abs(height - target_height) <= tolerance
    
    return width_ok and height_ok, (width, height)


def analyze_content_preservation(original_img, result_img):
    """
    Analyze if the original content was preserved during canvas expansion.
    Check for proper centering and no scaling/distortion.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Calculate expected position of original content in expanded canvas
    expected_x_offset = (result_w - orig_w) // 2
    expected_y_offset = (result_h - orig_h) // 2
    
    # Convert images to arrays for analysis
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Extract the region where original content should be positioned
    if (expected_x_offset >= 0 and expected_y_offset >= 0 and 
        expected_x_offset + orig_w <= result_w and expected_y_offset + orig_h <= result_h):
        
        extracted_region = result_array[expected_y_offset:expected_y_offset + orig_h, 
                                      expected_x_offset:expected_x_offset + orig_w]
        
        # Calculate similarity between original and extracted region
        diff = np.abs(orig_array.astype(np.float32) - extracted_region.astype(np.float32))
        mean_diff = np.mean(diff)
        max_diff = np.max(diff)
        
        # Content is preserved if the difference is minimal
        content_preserved = mean_diff < 10  # Average difference less than 10 intensity units
        properly_centered = True  # Position calculation was successful
        
        logging.debug(f"Content analysis - mean_diff: {mean_diff:.2f}, max_diff: {max_diff:.2f}")
        
    else:
        # Original content doesn't fit in expected centered position
        content_preserved = False
        properly_centered = False
        mean_diff = float('inf')
        
        logging.debug("Original content doesn't fit in expected centered position")
    
    return {
        'content_preserved': content_preserved,
        'properly_centered': properly_centered,
        'mean_difference': mean_diff if mean_diff != float('inf') else -1,
        'expected_position': (expected_x_offset, expected_y_offset),
        'expansion_ratio': (result_w * result_h) / (orig_w * orig_h)
    }


def detect_canvas_expansion(original_img, result_img):
    """
    Detect if canvas was expanded (vs. image being scaled).
    Canvas expansion should show background fill in new areas.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Calculate area increase
    orig_area = orig_w * orig_h
    result_area = result_w * result_h
    area_increase = result_area - orig_area
    area_increase_ratio = result_area / orig_area
    
    # Significant expansion should be at least 40% area increase
    significant_expansion = area_increase_ratio >= 1.4
    
    # Check for background areas (new canvas areas should be uniform color, typically white)
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    
    # Check corners for uniform background color (evidence of canvas expansion)
    corner_size = 50  # Check 50x50 pixel corners
    
    corners = []
    if result_w > corner_size and result_h > corner_size:
        # Top-left corner
        corners.append(result_array[:corner_size, :corner_size])
        # Top-right corner  
        corners.append(result_array[:corner_size, -corner_size:])
        # Bottom-left corner
        corners.append(result_array[-corner_size:, :corner_size])
        # Bottom-right corner
        corners.append(result_array[-corner_size:, -corner_size:])
    
    has_uniform_background = False
    if corners:
        # Check if corners have low variance (uniform color)
        corner_variances = []
        for corner in corners:
            # Calculate variance across all color channels
            variance = np.var(corner)
            corner_variances.append(variance)
        
        avg_corner_variance = np.mean(corner_variances)
        has_uniform_background = avg_corner_variance < 100  # Low variance indicates uniform color
        
        logging.debug(f"Corner variance analysis: {corner_variances}, avg: {avg_corner_variance:.2f}")
    
    return {
        'significant_expansion': significant_expansion,
        'area_increase_ratio': area_increase_ratio,
        'area_increase': area_increase,
        'has_uniform_background': has_uniform_background,
        'dimension_change': (result_w - orig_w, result_h - orig_h)
    }


def check_canvas_resize(traj, env_info, task_info):
    """
    Main verifier function for canvas resize task.
    Checks:
    1. Canvas dimensions are 1000x800 pixels (±5px tolerance)
    2. Original content is preserved and properly centered
    3. Canvas was expanded (not scaled)
    4. Significant area increase occurred
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
        "/home/ga/Desktop/expanded_canvas.jpg",
        "/home/ga/Desktop/expanded_canvas.png",
        "/home/ga/Desktop/expanded_canvas.jpeg",
        "/home/ga/Desktop/landscape_canvas_expanded.jpg",
        "/home/ga/Desktop/canvas_resized.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_canvas.jpg",
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
        
        # Check if dimensions match target (1000x800)
        dimensions_correct, actual_dims = check_canvas_dimensions(result_image, 1000, 800, tolerance=5)
        
        # Analyze content preservation and centering
        content_analysis = analyze_content_preservation(original_image, result_image)
        
        # Detect canvas expansion characteristics
        expansion_analysis = detect_canvas_expansion(original_image, result_image)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Target size: (1000, 800)")
        feedback_parts.append(f"Dimensions correct: {'✅' if dimensions_correct else '❌'}")
        feedback_parts.append(f"Significant expansion: {'✅' if expansion_analysis['significant_expansion'] else '❌'}")
        feedback_parts.append(f"Expansion ratio: {expansion_analysis['area_increase_ratio']:.2f}")
        feedback_parts.append(f"Content preserved: {'✅' if content_analysis['content_preserved'] else '❌'}")
        feedback_parts.append(f"Properly centered: {'✅' if content_analysis['properly_centered'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimensions_correct:
            criteria_met += 1
        if expansion_analysis['significant_expansion']:
            criteria_met += 1
        if content_analysis['content_preserved']:
            criteria_met += 1
        if content_analysis['properly_centered']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect canvas expansion!")
        elif passed:
            feedback_parts.append("✅ Good canvas expansion!")
        else:
            feedback_parts.append("❌ Canvas expansion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in canvas resize verification: {e}")
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
    result = check_canvas_resize([], {}, {})
    print(f"Test result: {result}")