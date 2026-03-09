#!/usr/bin/env python3
"""
Verifier for GIMP feather selection task.
Checks if a rectangular selection was feathered and filled with gradual edges.
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


def detect_filled_region(original_img, result_img):
    """
    Detect the filled region by comparing original and result images.
    Returns the bounding box and properties of the filled area.
    """
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB for analysis
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Find significantly changed pixels (likely the filled area)
    threshold = max(np.percentile(diff_magnitude, 95), 30)
    changed_pixels = diff_magnitude > threshold
    
    # Find bounding box of changed region
    changed_coords = np.where(changed_pixels)
    if len(changed_coords[0]) == 0:
        return None  # No significant changes found
    
    y_min, y_max = np.min(changed_coords[0]), np.max(changed_coords[0])
    x_min, x_max = np.min(changed_coords[1]), np.max(changed_coords[1])
    
    # Calculate properties
    width = x_max - x_min
    height = y_max - y_min
    center_x = (x_min + x_max) // 2
    center_y = (y_min + y_max) // 2
    area = np.sum(changed_pixels)
    
    img_width, img_height = result_img.size
    
    # Check if roughly centered (within 30% of center)
    is_centered = (abs(center_x - img_width//2) < img_width * 0.3 and 
                  abs(center_y - img_height//2) < img_height * 0.3)
    
    return {
        'bbox': (x_min, y_min, x_max, y_max),
        'width': width,
        'height': height,
        'center': (center_x, center_y),
        'area': area,
        'is_centered': is_centered,
        'change_percentage': (area / (img_width * img_height)) * 100
    }


def analyze_edge_gradients(result_img, filled_region):
    """
    Analyze edge gradients to detect feathering.
    Samples perpendicular profiles along edges to measure transition width.
    """
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    img_array = np.array(result_gray)
    x_min, y_min, x_max, y_max = filled_region['bbox']
    
    # Sample points along each edge for gradient analysis
    sample_points = []
    
    # Top edge
    for x in range(x_min + 20, x_max - 20, max(1, (x_max - x_min) // 8)):
        sample_points.append(('top', x, y_min))
    
    # Bottom edge  
    for x in range(x_min + 20, x_max - 20, max(1, (x_max - x_min) // 8)):
        sample_points.append(('bottom', x, y_max))
    
    # Left edge
    for y in range(y_min + 20, y_max - 20, max(1, (y_max - y_min) // 8)):
        sample_points.append(('left', x_min, y))
    
    # Right edge
    for y in range(y_min + 20, y_max - 20, max(1, (y_max - y_min) // 8)):
        sample_points.append(('right', x_max, y))
    
    transition_widths = []
    gradients = []
    
    for edge, x, y in sample_points:
        try:
            # Extract perpendicular profile across the edge
            profile_length = 60
            
            if edge in ['top', 'bottom']:
                # Vertical profile for horizontal edges
                start_y = max(0, y - profile_length//2)
                end_y = min(img_array.shape[0], y + profile_length//2)
                if x < img_array.shape[1]:
                    profile = img_array[start_y:end_y, x]
                else:
                    continue
            else:
                # Horizontal profile for vertical edges
                start_x = max(0, x - profile_length//2)
                end_x = min(img_array.shape[1], x + profile_length//2)
                if y < img_array.shape[0]:
                    profile = img_array[y, start_x:end_x]
                else:
                    continue
            
            if len(profile) < 10:
                continue
            
            # Calculate gradient (rate of change)
            gradient = np.abs(np.diff(profile.astype(np.float32)))
            
            # Find transition zone - where gradient is above threshold
            gradient_threshold = np.std(gradient) if len(gradient) > 0 else 0
            if gradient_threshold < 5:
                gradient_threshold = 5
            
            transition_pixels = np.sum(gradient > gradient_threshold)
            
            if transition_pixels > 5:  # Valid transition detected
                transition_widths.append(transition_pixels)
                gradients.append(np.mean(gradient))
        
        except Exception as e:
            logging.debug(f"Error analyzing edge at {edge} ({x}, {y}): {e}")
            continue
    
    if len(transition_widths) == 0:
        return {'avg_transition_width': 0, 'has_soft_edges': False, 'consistent_feathering': False}
    
    avg_width = np.mean(transition_widths)
    width_std = np.std(transition_widths)
    
    # Feathered edges should have transition width around 2*feather_radius (40px for 20px feather)
    expected_width_range = (30, 50)  # Allow some tolerance
    has_appropriate_width = expected_width_range[0] <= avg_width <= expected_width_range[1]
    
    # Edges should be consistently soft (low standard deviation in transition widths)
    consistent_feathering = width_std < avg_width * 0.4
    
    # Soft edges should have gradual transitions (not sharp)
    has_soft_edges = avg_width >= 15  # Minimum transition width for "soft"
    
    return {
        'avg_transition_width': avg_width,
        'width_std': width_std,
        'has_soft_edges': has_soft_edges,
        'appropriate_feather_width': has_appropriate_width,
        'consistent_feathering': consistent_feathering,
        'num_samples': len(transition_widths)
    }


def check_fill_color_characteristics(result_img, filled_region):
    """
    Analyze the fill color to check if it's white or bright colored as expected.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    img_array = np.array(result_img)
    x_min, y_min, x_max, y_max = filled_region['bbox']
    
    # Sample center area of filled region (avoid edges which may be feathered)
    center_margin = 20
    center_x_min = x_min + center_margin
    center_x_max = x_max - center_margin
    center_y_min = y_min + center_margin
    center_y_max = y_max - center_margin
    
    if center_x_max <= center_x_min or center_y_max <= center_y_min:
        # Region too small, sample the whole area
        center_region = img_array[y_min:y_max, x_min:x_max]
    else:
        center_region = img_array[center_y_min:center_y_max, center_x_min:center_x_max]
    
    if center_region.size == 0:
        return {'is_bright_fill': False, 'avg_brightness': 0}
    
    # Calculate average brightness of center region
    avg_color = np.mean(center_region.reshape(-1, 3), axis=0)
    avg_brightness = np.mean(avg_color)
    
    # Check if fill is bright/white (brightness > 180 indicates white/bright fill)
    is_bright_fill = avg_brightness > 180
    
    return {
        'is_bright_fill': is_bright_fill,
        'avg_brightness': avg_brightness,
        'avg_color': avg_color
    }


def check_feather_selection(traj, env_info, task_info):
    """
    Main verifier function for feather selection task.
    Checks:
    1. A filled region is detected in the center area
    2. Edges show soft, gradual transitions (not sharp)
    3. Transition width approximates expected feather radius
    4. Feathering is consistent across edges
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
        "/home/ga/Desktop/feathered_fill.jpg",
        "/home/ga/Desktop/feathered_fill.png", 
        "/home/ga/Desktop/feathered_fill.jpeg",
        "/home/ga/Desktop/landscape_feathered.jpg",
        "/home/ga/Desktop/feather_selection.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_feather.jpg",
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
        
        # Detect the filled region
        filled_region = detect_filled_region(original_image, result_image)
        
        if filled_region is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No significant filled region detected. Make sure to create a selection, feather it, and fill it."
            }
        
        # Analyze edge gradients for feathering
        edge_analysis = analyze_edge_gradients(result_image, filled_region)
        
        # Check fill color characteristics
        color_analysis = check_fill_color_characteristics(result_image, filled_region)
        
        # Check if image was modified significantly
        modification_threshold = 5.0  # At least 5% of pixels should be changed
        meaningfully_modified = filled_region['change_percentage'] >= modification_threshold
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Filled region detected: ✅")
        feedback_parts.append(f"Region size: {filled_region['width']}x{filled_region['height']}")
        feedback_parts.append(f"Region centered: {'✅' if filled_region['is_centered'] else '❌'}")
        feedback_parts.append(f"Pixels changed: {filled_region['change_percentage']:.1f}%")
        feedback_parts.append(f"Avg transition width: {edge_analysis['avg_transition_width']:.1f}px")
        feedback_parts.append(f"Bright fill color: {'✅' if color_analysis['is_bright_fill'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Filled region detected (already confirmed above)
        criteria_met += 1
        
        # 2. Soft edges present (transition width >= 15px)
        if edge_analysis['has_soft_edges']:
            criteria_met += 1
        feedback_parts.append(f"Soft edges present: {'✅' if edge_analysis['has_soft_edges'] else '❌'}")
        
        # 3. Appropriate feather width (30-50px range for 20px feather)
        if edge_analysis['appropriate_feather_width']:
            criteria_met += 1
        feedback_parts.append(f"Appropriate feather width: {'✅' if edge_analysis['appropriate_feather_width'] else '❌'}")
        
        # 4. Consistent feathering across edges
        if edge_analysis['consistent_feathering']:
            criteria_met += 1
        feedback_parts.append(f"Consistent feathering: {'✅' if edge_analysis['consistent_feathering'] else '❌'}")
        
        # 5. Image meaningfully modified
        if meaningfully_modified:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if meaningfully_modified else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent feathered selection!")
        elif passed:
            feedback_parts.append("✅ Good feathered selection!")
        else:
            feedback_parts.append("❌ Feathered selection needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in feather selection verification: {e}")
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
    result = check_feather_selection([], {}, {})
    print(f"Test result: {result}")