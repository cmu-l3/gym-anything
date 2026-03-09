#!/usr/bin/env python3
"""
Verifier for GIMP rectangle select and fill task.
Checks if a red rectangle was added to the center of the image.
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


def detect_filled_rectangles(original_img, result_img):
    """
    Detect rectangular filled regions using delta analysis.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB arrays
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    delta = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Find significantly changed regions
    magnitude = np.sqrt(np.sum(delta ** 2, axis=2))
    threshold = max(np.percentile(magnitude, 90), 40)
    significant_changes = magnitude > threshold
    
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(significant_changes)
        objects = find_objects(labeled_regions)
        
        rectangles = []
        total_pixels = orig_array.shape[0] * orig_array.shape[1]
        
        for i, obj in enumerate(objects):
            if obj is None:
                continue
            
            region_mask = (labeled_regions == i + 1)
            area = np.sum(region_mask)
            
            # Filter by size (must be substantial but not too large)
            min_area = total_pixels * 0.15  # At least 15% of image
            max_area = total_pixels * 0.50  # At most 50% of image
            
            if min_area <= area <= max_area:
                y_slice, x_slice = obj
                
                # Calculate rectangularity score
                bbox_area = (y_slice.stop - y_slice.start) * (x_slice.stop - x_slice.start)
                rectangularity = area / bbox_area if bbox_area > 0 else 0
                
                # Extract color from filled region
                filled_pixels = result_array[region_mask]
                avg_color = np.mean(filled_pixels, axis=0)
                
                if rectangularity > 0.7:  # Reasonably rectangular
                    rectangles.append({
                        'bbox': (x_slice.start, y_slice.start, x_slice.stop, y_slice.stop),
                        'area': area,
                        'rectangularity': rectangularity,
                        'color': avg_color,
                        'center': ((x_slice.start + x_slice.stop) / 2, 
                                  (y_slice.start + y_slice.stop) / 2),
                        'area_percentage': (area / total_pixels) * 100
                    })
        
        # Sort by area (largest first)
        rectangles.sort(key=lambda x: x['area'], reverse=True)
        return rectangles
        
    except ImportError:
        # Fallback grid-based approach
        logging.warning("scipy not available, using fallback detection")
        return grid_based_rectangle_detection(significant_changes, result_array)


def grid_based_rectangle_detection(significant_changes, result_array):
    """Fallback rectangle detection using grid analysis."""
    height, width = significant_changes.shape
    rectangles = []
    
    # Divide into grid and look for high change density
    rows, cols = 6, 8
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
            
            if change_density > 0.3:  # High change density
                area = (x2-x1) * (y2-y1)
                total_pixels = height * width
                
                if 0.15 <= (area / total_pixels) <= 0.50:
                    # Extract average color from this region
                    region_pixels = result_array[y1:y2, x1:x2].reshape(-1, 3)
                    avg_color = np.mean(region_pixels, axis=0)
                    
                    rectangles.append({
                        'bbox': (x1, y1, x2, y2),
                        'area': area,
                        'rectangularity': 0.9,  # Grid cells are rectangular
                        'color': avg_color,
                        'center': ((x1 + x2) / 2, (y1 + y2) / 2),
                        'area_percentage': (area / total_pixels) * 100
                    })
    
    rectangles.sort(key=lambda x: x['area'], reverse=True)
    return rectangles


def verify_red_color(rgb_color):
    """Verify color is predominantly red."""
    r, g, b = rgb_color
    # Red should be significantly higher than green and blue
    return r > 200 and r > (g + 50) and r > (b + 50)


def verify_center_position(rect_center, image_shape):
    """Verify rectangle is positioned near center."""
    img_height, img_width = image_shape[:2]
    img_center = (img_width / 2, img_height / 2)
    
    # Distance from image center
    distance = np.sqrt((rect_center[0] - img_center[0])**2 + 
                      (rect_center[1] - img_center[1])**2)
    
    # Allow up to 40% deviation from center (quite generous)
    max_distance = min(img_width, img_height) * 0.4
    return distance <= max_distance


def check_rectangle_fill(traj, env_info, task_info):
    """
    Main verifier function for rectangle select and fill task.
    Checks:
    1. Rectangle was detected in the image
    2. Rectangle is filled with red color
    3. Rectangle is appropriately sized (15-50% of image area)
    4. Rectangle is positioned near center
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
        "/home/ga/Desktop/rectangle_overlay.jpg",
        "/home/ga/Desktop/rectangle_overlay.png", 
        "/home/ga/Desktop/rectangle_overlay.jpeg",
        "/home/ga/Desktop/landscape_overlay.jpg",
        "/home/ga/Desktop/landscape_rectangle.jpg",
        "/home/ga/Desktop/landscape_image_edited.jpg"
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
        
        # Detect rectangular regions
        rectangles = detect_filled_rectangles(original_image, result_image)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image), 
                                            np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Rectangles detected: {len(rectangles)}")
        
        if rectangles:
            best_rect = rectangles[0]  # Largest rectangle
            feedback_parts.append(f"Best rectangle area: {best_rect['area_percentage']:.1f}%")
            feedback_parts.append(f"Rectangle center: ({best_rect['center'][0]:.0f}, {best_rect['center'][1]:.0f})")
            feedback_parts.append(f"Rectangle color (RGB): ({best_rect['color'][0]:.0f}, {best_rect['color'][1]:.0f}, {best_rect['color'][2]:.0f})")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Rectangle detected
        rectangle_detected = len(rectangles) > 0
        if rectangle_detected:
            criteria_met += 1
        feedback_parts.append(f"Rectangle detected: {'✅' if rectangle_detected else '❌'}")
        
        if rectangle_detected:
            best_rect = rectangles[0]
            
            # 2. Red color verification
            is_red = verify_red_color(best_rect['color'])
            if is_red:
                criteria_met += 1
            feedback_parts.append(f"Red color applied: {'✅' if is_red else '❌'}")
            
            # 3. Appropriate size (15-50% of image area)
            good_size = 15 <= best_rect['area_percentage'] <= 50
            if good_size:
                criteria_met += 1
            feedback_parts.append(f"Appropriate size: {'✅' if good_size else '❌'}")
            
            # 4. Center positioning
            centered = verify_center_position(best_rect['center'], np.array(result_image).shape)
            if centered:
                criteria_met += 1
            feedback_parts.append(f"Center positioning: {'✅' if centered else '❌'}")
        else:
            feedback_parts.append("Red color applied: ❌")
            feedback_parts.append("Appropriate size: ❌")
            feedback_parts.append("Center positioning: ❌")
        
        # 5. Image modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 80  # Need at least 4/5 criteria (80%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rectangle overlay!")
        elif passed:
            feedback_parts.append("✅ Good rectangle overlay!")
        else:
            feedback_parts.append("❌ Rectangle overlay needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rectangle fill verification: {e}")
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
    result = check_rectangle_fill([], {}, {})
    print(f"Test result: {result}")