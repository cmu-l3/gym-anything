#!/usr/bin/env python3
"""
Verifier for GIMP add border task.
Checks if a colored border was added around the image.
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


def check_dimension_increase(original_img, result_img):
    """Check if image dimensions increased appropriately for border."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    width_increase = result_w - orig_w
    height_increase = result_h - orig_h
    
    # Check both dimensions increased
    if width_increase < 20 or height_increase < 20:
        return False, f"Insufficient dimension increase: {width_increase}x{height_increase}"
    
    # Check increases are similar (uniform border)
    if abs(width_increase - height_increase) > 20:
        return False, f"Non-uniform border: width+{width_increase}, height+{height_increase}"
    
    # Check not excessively large
    if width_increase > 200 or height_increase > 200:
        return False, f"Border too large: {width_increase}x{height_increase}"
    
    border_size = width_increase // 2  # Approximate border size per side
    return True, f"Good border size: ~{border_size}px per side"


def analyze_border_color(result_img):
    """Detect and validate border color uniformity."""
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    h, w = result_array.shape[:2]
    
    # Sample edge regions (outer portion of image)
    edge_thickness = max(15, min(w, h) // 20)  # At least 15px, or 5% of smallest dimension
    
    # Extract edge regions
    top_edge = result_array[:edge_thickness, :]
    bottom_edge = result_array[-edge_thickness:, :]
    left_edge = result_array[:, :edge_thickness]
    right_edge = result_array[:, -edge_thickness:]
    
    # Calculate mean colors for each edge
    edge_colors = [
        np.mean(top_edge.reshape(-1, 3), axis=0),
        np.mean(bottom_edge.reshape(-1, 3), axis=0),
        np.mean(left_edge.reshape(-1, 3), axis=0),
        np.mean(right_edge.reshape(-1, 3), axis=0)
    ]
    
    # Check uniformity across edges (low variance = uniform color)
    edge_colors = np.array(edge_colors)
    color_variance = np.var(edge_colors, axis=0)
    max_variance = np.max(color_variance)
    
    # Check if edge colors are distinct from center
    center_region = result_array[h//4:3*h//4, w//4:3*w//4]
    center_color = np.mean(center_region.reshape(-1, 3), axis=0)
    border_color = np.mean(edge_colors, axis=0)
    
    color_distance = np.sqrt(np.sum((border_color - center_color) ** 2))
    
    is_uniform = max_variance < 800  # Reasonable variance threshold
    is_distinct = color_distance > 30  # Minimum color difference
    
    return {
        'is_uniform': is_uniform,
        'is_distinct': is_distinct,
        'max_variance': max_variance,
        'color_distance': color_distance,
        'border_color': border_color,
        'center_color': center_color
    }


def verify_content_preserved(original_img, result_img):
    """Check that original content exists in center of result."""
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Extract center region from result (should match original size)
    h_orig, w_orig = orig_array.shape[:2]
    h_result, w_result = result_array.shape[:2]
    
    # Calculate center position
    y_start = (h_result - h_orig) // 2
    x_start = (w_result - w_orig) // 2
    y_end = y_start + h_orig
    x_end = x_start + w_orig
    
    # Handle edge cases where result is not larger than original
    if y_start < 0 or x_start < 0 or y_end > h_result or x_end > w_result:
        return False, "Result image dimensions don't allow center extraction"
    
    center_region = result_array[y_start:y_end, x_start:x_end]
    
    # Compare with original using correlation
    if orig_array.shape != center_region.shape:
        return False, f"Shape mismatch: {orig_array.shape} vs {center_region.shape}"
    
    # Calculate structural similarity using normalized correlation
    orig_flat = orig_array.astype(np.float32).flatten()
    center_flat = center_region.astype(np.float32).flatten()
    
    # Normalize
    orig_norm = orig_flat - np.mean(orig_flat)
    center_norm = center_flat - np.mean(center_flat)
    
    # Calculate correlation
    if np.std(orig_norm) == 0 or np.std(center_norm) == 0:
        correlation = 1.0 if np.array_equal(orig_array, center_region) else 0.0
    else:
        correlation = np.corrcoef(orig_norm, center_norm)[0, 1]
    
    similarity = max(0, correlation)  # Ensure non-negative
    content_preserved = similarity > 0.85  # High similarity means content preserved
    
    return content_preserved, f"Content similarity: {similarity:.3f}"


def check_border_added(traj, env_info, task_info):
    """
    Main verifier function for add border task.
    Checks:
    1. Image dimensions increased appropriately
    2. Edge regions have uniform, distinct border color
    3. Original content preserved in center
    4. Border applied uniformly to all sides
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
        "/home/ga/Desktop/bordered_image.jpg",
        "/home/ga/Desktop/bordered_image.png", 
        "/home/ga/Desktop/bordered_image.jpeg",
        "/home/ga/Desktop/sample_image_bordered.jpg",
        "/home/ga/Desktop/sample_border.jpg",
        "/home/ga/Desktop/border_sample.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/sample_image.jpg",
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
        
        # Check if dimensions increased appropriately
        dimensions_ok, dim_feedback = check_dimension_increase(original_image, result_image)
        
        # Analyze border color uniformity and distinctness
        border_analysis = analyze_border_color(result_image)
        
        # Check if original content is preserved in center
        content_ok, content_feedback = verify_content_preserved(original_image, result_image)
        
        # Check if image was meaningfully modified
        images_different = original_image.size != result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Dimensions increased: {'✅' if dimensions_ok else '❌'}")
        feedback_parts.append(dim_feedback)
        feedback_parts.append(f"Border uniform: {'✅' if border_analysis['is_uniform'] else '❌'}")
        feedback_parts.append(f"Border distinct: {'✅' if border_analysis['is_distinct'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_ok else '❌'}")
        feedback_parts.append(content_feedback)
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimensions_ok:
            criteria_met += 1
        if border_analysis['is_uniform'] and border_analysis['is_distinct']:
            criteria_met += 1
        if content_ok:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect border added!")
        elif passed:
            feedback_parts.append("✅ Good border added!")
        else:
            feedback_parts.append("❌ Border addition needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in add border verification: {e}")
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
    result = check_border_added([], {}, {})
    print(f"Test result: {result}")