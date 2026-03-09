#!/usr/bin/env python3
"""
Verifier for GIMP rectangle selection and fill task.
Checks if a red rectangle was added to the upper-left area of the image.
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


def detect_red_regions(img):
    """
    Detect red-colored regions in the image.
    Returns regions with their properties.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    
    # Define red color ranges (high R, low G, low B)
    red_mask = (
        (img_array[:, :, 0] >= 200) &  # High red (≥200)
        (img_array[:, :, 1] <= 100) &  # Low green (≤100)  
        (img_array[:, :, 2] <= 100)    # Low blue (≤100)
    )
    
    # Find connected components of red pixels
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(red_mask)
        
        red_rectangles = []
        for i in range(1, num_regions + 1):
            # Get bounding box of this region
            objects = find_objects(labeled_regions == i)
            if not objects or objects[0] is None:
                continue
                
            y_slice, x_slice = objects[0]
            region_mask = (labeled_regions == i)
            
            # Calculate region properties
            x1, x2 = x_slice.start, x_slice.stop
            y1, y2 = y_slice.start, y_slice.stop
            width_px = x2 - x1
            height_px = y2 - y1
            area = np.sum(region_mask)
            
            # Filter for reasonably sized rectangular regions
            if width_px >= 50 and height_px >= 50 and area >= 2500:
                # Calculate center position
                center_x = (x1 + x2) // 2
                center_y = (y1 + y2) // 2
                
                # Check if region is roughly rectangular (area should be close to bounding box area)
                bounding_area = width_px * height_px
                fill_ratio = area / bounding_area if bounding_area > 0 else 0
                
                # Good rectangles should have fill ratio > 0.7 (allowing for some imperfection)
                if fill_ratio > 0.7:
                    red_rectangles.append({
                        'bbox': (x1, y1, x2, y2),
                        'center': (center_x, center_y),
                        'width': width_px,
                        'height': height_px,
                        'area': area,
                        'fill_ratio': fill_ratio
                    })
        
        # Sort by area (largest first)
        red_rectangles.sort(key=lambda x: x['area'], reverse=True)
        return red_rectangles
        
    except ImportError:
        # Fallback: grid-based approach if scipy not available
        logging.warning("SciPy not available, using grid-based red detection")
        return grid_based_red_detection(red_mask, img_array.shape)


def grid_based_red_detection(red_mask, img_shape):
    """Fallback method for detecting red regions using grid analysis."""
    height, width = img_shape[:2]
    regions = []
    
    # Divide into grid and look for red-dense areas
    grid_rows, grid_cols = 8, 8
    cell_height = height // grid_rows
    cell_width = width // grid_cols
    
    for r in range(grid_rows - 1):  # Allow for larger rectangles
        for c in range(grid_cols - 1):
            # Check 2x2 cell blocks for red density
            y1 = r * cell_height
            y2 = min((r + 2) * cell_height, height)
            x1 = c * cell_width
            x2 = min((c + 2) * cell_width, width)
            
            cell_red = red_mask[y1:y2, x1:x2]
            red_density = np.mean(cell_red)
            
            # If more than 50% of the block is red, consider it a rectangle
            if red_density > 0.5:
                regions.append({
                    'bbox': (x1, y1, x2, y2),
                    'center': ((x1 + x2) // 2, (y1 + y2) // 2),
                    'width': x2 - x1,
                    'height': y2 - y1,
                    'area': (x2 - x1) * (y2 - y1),
                    'fill_ratio': red_density
                })
    
    return regions


def check_upper_left_positioning(rectangles, img_size):
    """
    Check if any detected rectangles are positioned in the upper-left quadrant.
    """
    width, height = img_size
    
    # Define upper-left quadrant bounds
    upper_left_bounds = {
        'x_max': width // 2,    # Left half of image
        'y_max': height // 2    # Upper half of image
    }
    
    positioned_correctly = []
    
    for rect in rectangles:
        center_x, center_y = rect['center']
        
        # Check if rectangle center is in upper-left quadrant
        if center_x <= upper_left_bounds['x_max'] and center_y <= upper_left_bounds['y_max']:
            positioned_correctly.append(rect)
            logging.debug(f"Found rectangle in upper-left: center=({center_x}, {center_y}), size=({rect['width']}x{rect['height']})")
    
    return positioned_correctly


def analyze_image_changes(original_img, result_img):
    """
    Analyze what changes were made between original and result images.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Count significantly changed pixels (>30 intensity units change)
    if len(orig_array.shape) == 3:  # Color image
        magnitude_change = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        magnitude_change = diff
    
    significant_changes = np.sum(magnitude_change > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'significantly_modified': change_percentage > 1.0  # At least 1% of pixels changed
    }


def check_rectangle_selection_fill(traj, env_info, task_info):
    """
    Main verifier function for rectangle selection and fill task.
    Checks:
    1. Red rectangle was added to the image
    2. Rectangle is positioned in upper-left quadrant
    3. Rectangle is appropriately sized (≥50x50 pixels)
    4. Fill is clean and complete
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
        "/home/ga/Desktop/red_rectangle.jpg",
        "/home/ga/Desktop/red_rectangle.png", 
        "/home/ga/Desktop/red_rectangle.jpeg",
        "/home/ga/Desktop/landscape_rectangle.jpg",
        "/home/ga/Desktop/landscape_base_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_base.jpg",
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
        
        # Detect red rectangular regions in result image
        red_rectangles = detect_red_regions(result_image)
        
        # Check if any rectangles are positioned in upper-left
        upper_left_rectangles = check_upper_left_positioning(red_rectangles, result_image.size)
        
        # Analyze image changes
        change_analysis = analyze_image_changes(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Red rectangles detected: {len(red_rectangles)}")
        feedback_parts.append(f"Upper-left rectangles: {len(upper_left_rectangles)}")
        feedback_parts.append(f"Image changed: {change_analysis['change_percentage']:.1f}% pixels modified")
        
        if upper_left_rectangles:
            best_rect = upper_left_rectangles[0]  # Largest rectangle in upper-left
            feedback_parts.append(f"Best rectangle: {best_rect['width']}x{best_rect['height']} at center {best_rect['center']}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Red rectangle detected
        if len(red_rectangles) > 0:
            criteria_met += 1
        feedback_parts.append(f"Red rectangle detected: {'✅' if len(red_rectangles) > 0 else '❌'}")
        
        # 2. Rectangle positioned in upper-left
        if len(upper_left_rectangles) > 0:
            criteria_met += 1
        feedback_parts.append(f"Positioned in upper-left: {'✅' if len(upper_left_rectangles) > 0 else '❌'}")
        
        # 3. Rectangle adequately sized
        adequate_size = False
        if upper_left_rectangles:
            best_rect = upper_left_rectangles[0]
            adequate_size = best_rect['width'] >= 50 and best_rect['height'] >= 50
        if adequate_size:
            criteria_met += 1
        feedback_parts.append(f"Adequate size (≥50x50): {'✅' if adequate_size else '❌'}")
        
        # 4. Clean fill (high fill ratio)
        clean_fill = False
        if upper_left_rectangles:
            best_rect = upper_left_rectangles[0]
            clean_fill = best_rect['fill_ratio'] > 0.7
        if clean_fill:
            criteria_met += 1
        feedback_parts.append(f"Clean rectangular fill: {'✅' if clean_fill else '❌'}")
        
        # 5. Image meaningfully modified
        if change_analysis['significantly_modified']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['significantly_modified'] else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) but we'll use 75% threshold
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rectangle selection and fill!")
        elif passed:
            feedback_parts.append("✅ Good rectangle selection and fill!")
        else:
            feedback_parts.append("❌ Rectangle selection and fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rectangle selection verification: {e}")
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
    result = check_rectangle_selection_fill([], {}, {})
    print(f"Test result: {result}")