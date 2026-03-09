#!/usr/bin/env python3
"""
Verifier for GIMP rectangle selection and fill task.
Checks if a blue rectangle was created in the center area of the image.
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


def detect_blue_regions(img):
    """
    Detect blue-colored regions in the image.
    Returns blue pixel count and list of rectangular regions.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Define blue color ranges (accounts for JPEG compression)
    # Pure blue: R low, G low, B high
    blue_mask = (
        (img_array[:, :, 2] > 180) &  # High blue channel
        (img_array[:, :, 0] < 80) &   # Low red channel
        (img_array[:, :, 1] < 80)     # Low green channel
    )
    
    blue_pixel_count = np.sum(blue_mask)
    
    # Find connected components (rectangular regions)
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(blue_mask)
        
        rectangles = []
        for i in range(1, num_regions + 1):
            region_mask = (labeled_regions == i)
            area = np.sum(region_mask)
            
            if area >= 1000:  # Minimum size threshold
                coords = np.argwhere(region_mask)
                y_min, x_min = coords.min(axis=0)
                y_max, x_max = coords.max(axis=0)
                
                # Calculate centroid
                y_center = np.mean(coords[:, 0])
                x_center = np.mean(coords[:, 1])
                
                rectangles.append({
                    'bbox': (x_min, y_min, x_max, y_max),
                    'area': area,
                    'centroid': (x_center, y_center),
                    'width': x_max - x_min,
                    'height': y_max - y_min
                })
        
        # Sort by area (largest first)
        rectangles.sort(key=lambda x: x['area'], reverse=True)
        
    except ImportError:
        # Fallback: grid-based approach if scipy not available
        logging.warning("scipy not available, using fallback detection")
        rectangles = []
        
        height, width = blue_mask.shape
        # Simple grid-based detection
        for y in range(0, height, 50):
            for x in range(0, width, 50):
                y_end = min(y + 100, height)
                x_end = min(x + 100, width)
                
                region_mask = blue_mask[y:y_end, x:x_end]
                if np.sum(region_mask) > 500:  # Significant blue area
                    rectangles.append({
                        'bbox': (x, y, x_end, y_end),
                        'area': np.sum(region_mask),
                        'centroid': (x + 50, y + 50),
                        'width': x_end - x,
                        'height': y_end - y
                    })
        
        rectangles.sort(key=lambda x: x['area'], reverse=True)
    
    return blue_pixel_count, rectangles


def verify_center_position(rect_centroid, img_width, img_height):
    """
    Check if rectangle centroid is in the center area of the image.
    Center area is defined as middle 60% of width and height.
    """
    center_x, center_y = img_width / 2, img_height / 2
    
    # Rectangle centroid should be in middle 60% of image
    x_margin = img_width * 0.3
    y_margin = img_height * 0.3
    
    is_centered = (
        (center_x - x_margin <= rect_centroid[0] <= center_x + x_margin) and
        (center_y - y_margin <= rect_centroid[1] <= center_y + y_margin)
    )
    
    return is_centered


def analyze_rectangle_shape(rectangle):
    """
    Analyze if the detected region has rectangular characteristics.
    """
    width = rectangle['width']
    height = rectangle['height']
    area = rectangle['area']
    
    # Calculate expected area if it were a perfect rectangle
    expected_area = width * height
    
    # Rectangle should have area close to width * height
    area_ratio = area / expected_area if expected_area > 0 else 0
    
    # Good rectangle should have area ratio > 0.7 (accounting for anti-aliasing)
    is_rectangular = area_ratio > 0.7
    
    return {
        'area_ratio': area_ratio,
        'is_rectangular': is_rectangular,
        'aspect_ratio': width / height if height > 0 else float('inf')
    }


def check_rect_fill(traj, env_info, task_info):
    """
    Main verifier function for rectangle fill task.
    Checks:
    1. Blue region detected with adequate size
    2. Rectangle positioned in center area
    3. Appropriate size (not too small or too large)
    4. Rectangular shape characteristics
    5. Correct blue color
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
        "/home/ga/Desktop/blue_rectangle.jpg",
        "/home/ga/Desktop/blue_rectangle.png",
        "/home/ga/Desktop/blue_rectangle.jpeg",
        "/home/ga/Desktop/landscape_image_rect.jpg",
        "/home/ga/Desktop/landscape_filled.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_image.jpg",
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
        
        # Detect blue regions in result image
        blue_pixel_count, blue_rectangles = detect_blue_regions(result_image)
        
        # Check if image was modified (has blue pixels that weren't in original)
        original_blue_count, _ = detect_blue_regions(original_image)
        blue_added = blue_pixel_count > original_blue_count + 100  # At least 100 new blue pixels
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Blue pixels found: {blue_pixel_count}")
        feedback_parts.append(f"Blue regions detected: {len(blue_rectangles)}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Blue region detected (minimum 1,000 pixels)
        blue_region_detected = blue_pixel_count >= 1000
        if blue_region_detected:
            criteria_met += 1
        feedback_parts.append(f"Blue region detected: {'✅' if blue_region_detected else '❌'}")
        
        # 2. Appropriate size (1,000 - 150,000 pixels)
        appropriate_size = 1000 <= blue_pixel_count <= 150000
        if appropriate_size:
            criteria_met += 1
        feedback_parts.append(f"Appropriate size: {'✅' if appropriate_size else '❌'}")
        
        # 3. Center positioned
        center_positioned = False
        best_rectangle = None
        if blue_rectangles:
            best_rectangle = blue_rectangles[0]  # Largest rectangle
            center_positioned = verify_center_position(
                best_rectangle['centroid'], 
                result_image.width, 
                result_image.height
            )
            if center_positioned:
                criteria_met += 1
            feedback_parts.append(f"Center positioned: {'✅' if center_positioned else '❌'}")
            feedback_parts.append(f"Best rectangle: {best_rectangle['width']}x{best_rectangle['height']} at {best_rectangle['centroid']}")
        else:
            feedback_parts.append("Center positioned: ❌ (no rectangles found)")
        
        # 4. Rectangular shape
        rectangular_shape = False
        if best_rectangle:
            shape_analysis = analyze_rectangle_shape(best_rectangle)
            rectangular_shape = shape_analysis['is_rectangular']
            if rectangular_shape:
                criteria_met += 1
            feedback_parts.append(f"Rectangular shape: {'✅' if rectangular_shape else '❌'}")
            feedback_parts.append(f"Area ratio: {shape_analysis['area_ratio']:.2f}")
        else:
            feedback_parts.append("Rectangular shape: ❌ (no rectangles found)")
        
        # 5. Color accuracy (blue color detected)
        color_accurate = blue_pixel_count > 0
        if color_accurate:
            criteria_met += 1
        feedback_parts.append(f"Blue color detected: {'✅' if color_accurate else '❌'}")
        
        # Check if image was modified
        feedback_parts.append(f"Image modified: {'✅' if blue_added else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (75%)
        
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
        logging.error(f"Error in rect fill verification: {e}")
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
    result = check_rect_fill([], {}, {})
    print(f"Test result: {result}")