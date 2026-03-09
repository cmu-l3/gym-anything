#!/usr/bin/env python3
"""
Verifier for GIMP circle fill task.
Checks if a circular selection was created and filled with red color.
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


def detect_circle_regions_by_change(original_img, result_img):
    """
    Detect circular regions by analyzing pixel changes between original and result.
    Uses connected component analysis to identify filled areas.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    delta = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate magnitude of change for each pixel
    magnitude = np.sqrt(np.sum(delta ** 2, axis=2))
    
    # Threshold for significant changes
    threshold = max(np.percentile(magnitude, 95), 30)  # Top 5% or minimum 30 intensity units
    significant_changes = magnitude > threshold
    
    # Find connected components (regions of change)
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(significant_changes)
        objects = find_objects(labeled_regions)
        
        regions = []
        for i, obj in enumerate(objects):
            if obj is None:
                continue
                
            region_mask = (labeled_regions == i + 1)
            area = np.sum(region_mask)
            
            # Filter out small regions (noise)
            if area >= 100:  # Minimum area threshold
                y_slice, x_slice = obj
                region_info = {
                    'bbox': (x_slice.start, y_slice.start, x_slice.stop, y_slice.stop),
                    'area': area,
                    'center': ((x_slice.start + x_slice.stop) // 2, (y_slice.start + y_slice.stop) // 2),
                    'width': x_slice.stop - x_slice.start,
                    'height': y_slice.stop - y_slice.start,
                    'avg_change': np.mean(magnitude[region_mask])
                }
                regions.append(region_info)
        
        # Sort by area (largest first)
        regions.sort(key=lambda x: x['area'], reverse=True)
        return regions
        
    except ImportError:
        # Fallback: simple grid-based approach if scipy not available
        logging.warning("scipy not available, using fallback detection")
        height, width = magnitude.shape
        regions = []
        
        # Divide into grid cells and look for high change density
        rows, cols = 8, 8
        cell_height = height // rows
        cell_width = width // cols
        
        for r in range(rows):
            for c in range(cols):
                y1 = r * cell_height
                y2 = min((r + 1) * cell_height, height)
                x1 = c * cell_width
                x2 = min((c + 1) * cell_width, width)
                
                cell_changes = significant_changes[y1:y2, x1:x2]
                change_density = np.mean(cell_changes)
                
                if change_density > 0.2:  # At least 20% of pixels changed
                    avg_change = np.mean(magnitude[y1:y2, x1:x2])
                    area = (x2-x1) * (y2-y1)
                    regions.append({
                        'bbox': (x1, y1, x2, y2),
                        'area': area,
                        'center': ((x1 + x2) // 2, (y1 + y2) // 2),
                        'width': x2-x1,
                        'height': y2-y1,
                        'avg_change': avg_change
                    })
        
        regions.sort(key=lambda x: x['avg_change'], reverse=True)
        return regions


def calculate_circularity(region, result_img):
    """
    Calculate circularity of a region using contour analysis.
    Circularity = 4π × Area / Perimeter²
    Perfect circle = 1.0, acceptable threshold ≥ 0.65
    """
    try:
        from skimage import measure
        
        # Extract region from image
        x1, y1, x2, y2 = region['bbox']
        
        # Create binary mask of the region
        if result_img.mode != 'RGB':
            result_img = result_img.convert('RGB')
        
        result_array = np.array(result_img)
        region_img = result_array[y1:y2, x1:x2]
        
        # Convert to grayscale and threshold to create binary mask
        gray = np.mean(region_img, axis=2)
        binary = gray < np.mean(gray) - np.std(gray)  # Assume filled area is darker/different
        
        # Find contours
        contours = measure.find_contours(binary, 0.5)
        
        if not contours:
            return 0.0
        
        # Use the largest contour
        contour = max(contours, key=len)
        
        # Calculate area and perimeter
        area = measure.grid_points_in_poly(binary.shape, contour).sum()
        perimeter = len(contour)
        
        if perimeter == 0:
            return 0.0
        
        # Calculate circularity
        circularity = 4 * np.pi * area / (perimeter * perimeter)
        return min(circularity, 1.0)  # Cap at 1.0
        
    except ImportError:
        # Fallback: use width/height ratio as rough circularity measure
        width = region['width']
        height = region['height']
        
        if width == 0 or height == 0:
            return 0.0
        
        # Calculate aspect ratio circularity (how close to square)
        aspect_ratio = min(width, height) / max(width, height)
        return aspect_ratio  # Perfect square = 1.0


def analyze_region_color(region, result_img):
    """
    Analyze the color of a region to check if it's red.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    x1, y1, x2, y2 = region['bbox']
    
    # Extract pixels from the region
    region_pixels = result_array[y1:y2, x1:x2].reshape(-1, 3)
    
    # Calculate average color
    avg_color = np.mean(region_pixels, axis=0)
    
    # Check if color is red-ish (high R, low G and B)
    r, g, b = avg_color
    is_red = r >= 200 and g <= 80 and b <= 80  # Red criteria
    
    return {
        'avg_color': avg_color,
        'is_red': is_red,
        'red_ratio': r / 255.0
    }


def check_region_position(region, img_size):
    """
    Check if region is positioned in the central area of the image.
    """
    width, height = img_size
    center_x, center_y = region['center']
    
    # Define central area (center 70% of image)
    central_bounds = {
        'x_min': width * 0.15,
        'x_max': width * 0.85,
        'y_min': height * 0.15,
        'y_max': height * 0.85
    }
    
    is_centered = (central_bounds['x_min'] <= center_x <= central_bounds['x_max'] and
                   central_bounds['y_min'] <= center_y <= central_bounds['y_max'])
    
    return is_centered


def check_region_size(region, img_size):
    """
    Check if region has appropriate size (not too small or too large).
    """
    width, height = img_size
    total_pixels = width * height
    region_area = region['area']
    
    # Size should be between 2% and 30% of image area
    min_size = total_pixels * 0.02  # 2%
    max_size = total_pixels * 0.30  # 30%
    
    # Also check absolute pixel size (diameter roughly 100-500 pixels)
    diameter_approx = np.sqrt(region_area / np.pi) * 2
    size_ok = (min_size <= region_area <= max_size and 
               100 <= diameter_approx <= 500)
    
    return size_ok, diameter_approx


def check_circle_fill(traj, env_info, task_info):
    """
    Main verifier function for circle fill task.
    Checks:
    1. A circular shape was detected in the changed regions
    2. The shape is filled with red color
    3. The circle is positioned in the central area
    4. The circle has appropriate size
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
        "/home/ga/Desktop/circle_filled.png",
        "/home/ga/Desktop/circle_filled.jpg", 
        "/home/ga/Desktop/circle_filled.jpeg",
        "/home/ga/Desktop/background_image_circle.png",
        "/home/ga/Desktop/background_filled.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/background_image.jpg",
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
        
        # Detect regions that changed between original and result
        changed_regions = detect_circle_regions_by_change(original_image, result_image)
        
        if not changed_regions:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No significant changes detected in the image"
            }
        
        # Analyze the largest/most prominent region (most likely the filled circle)
        primary_region = changed_regions[0]
        
        # Calculate circularity
        circularity = calculate_circularity(primary_region, result_image)
        
        # Analyze color
        color_analysis = analyze_region_color(primary_region, result_image)
        
        # Check position
        is_centered = check_region_position(primary_region, result_image.size)
        
        # Check size
        size_ok, diameter = check_region_size(primary_region, result_image.size)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Regions detected: {len(changed_regions)}")
        feedback_parts.append(f"Primary region area: {primary_region['area']} px")
        feedback_parts.append(f"Estimated diameter: {diameter:.1f} px")
        feedback_parts.append(f"Region center: {primary_region['center']}")
        feedback_parts.append(f"Average color: RGB{tuple(int(c) for c in color_analysis['avg_color'])}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Circular shape (circularity ≥ 0.65)
        is_circular = circularity >= 0.65
        if is_circular:
            criteria_met += 1
        feedback_parts.append(f"Circular shape (≥0.65): {'✅' if is_circular else '❌'} ({circularity:.2f})")
        
        # 2. Red color
        if color_analysis['is_red']:
            criteria_met += 1
        feedback_parts.append(f"Red color: {'✅' if color_analysis['is_red'] else '❌'}")
        
        # 3. Centered position
        if is_centered:
            criteria_met += 1
        feedback_parts.append(f"Centered position: {'✅' if is_centered else '❌'}")
        
        # 4. Appropriate size
        if size_ok:
            criteria_met += 1
        feedback_parts.append(f"Appropriate size: {'✅' if size_ok else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect circle fill!")
        elif passed:
            feedback_parts.append("✅ Good circle fill!")
        else:
            feedback_parts.append("❌ Circle fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in circle fill verification: {e}")
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
    result = check_circle_fill([], {}, {})
    print(f"Test result: {result}")