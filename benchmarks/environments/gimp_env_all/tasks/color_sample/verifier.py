#!/usr/bin/env python3
"""
Verifier for GIMP color sampling task.
Checks if color was sampled from purple flower and applied to a rectangular selection.
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


def extract_source_color_from_flower(img, flower_region=(100, 50, 250, 200)):
    """
    Extract the dominant purple color from the flower area.
    Uses statistical analysis to handle natural color variation.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    # Extract flower region (approximate upper area where purple flower should be)
    try:
        flower_crop = img.crop(flower_region)
        flower_array = np.array(flower_crop)
        
        # Find pixels that are purple-ish (high red and blue, lower green)
        pixels = flower_array.reshape(-1, 3)
        
        # Filter for purple-like colors: R > 80, B > 80, G < R*0.8
        purple_mask = (pixels[:, 0] > 80) & (pixels[:, 2] > 80) & (pixels[:, 1] < pixels[:, 0] * 0.8)
        purple_pixels = pixels[purple_mask]
        
        if len(purple_pixels) > 0:
            # Use median color to avoid outliers
            source_color = np.median(purple_pixels, axis=0).astype(int)
        else:
            # Fallback: use median of entire flower region
            source_color = np.median(pixels, axis=0).astype(int)
        
        logging.debug(f"Extracted source color from flower: RGB{tuple(source_color)}")
        return source_color
    
    except Exception as e:
        logging.error(f"Error extracting flower color: {e}")
        # Return a default purple color if extraction fails
        return np.array([128, 64, 128])


def detect_filled_rectangles(original_img, result_img):
    """
    Detect rectangular areas that have been filled by comparing original and result images.
    Returns list of rectangle information.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate magnitude of change for each pixel
    magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Find significantly changed areas (likely filled rectangles)
    threshold = max(np.percentile(magnitude, 95), 30)  # Top 5% of changes or min 30 units
    changed_mask = magnitude > threshold
    
    rectangles = []
    height, width = magnitude.shape
    
    # Grid-based approach to find rectangular regions
    grid_size = 20  # Check 20x20 pixel blocks
    
    for y in range(0, height - grid_size, grid_size // 2):
        for x in range(0, width - grid_size, grid_size // 2):
            # Define potential rectangle bounds
            y2 = min(y + grid_size * 4, height)  # Allow rectangles up to 4 grid units tall
            x2 = min(x + grid_size * 4, width)   # Allow rectangles up to 4 grid units wide
            
            # Check if this region has significant changes
            region_changes = changed_mask[y:y2, x:x2]
            change_density = np.mean(region_changes)
            
            if change_density > 0.3:  # At least 30% of pixels changed
                region_area = (y2 - y) * (x2 - x)
                if region_area >= 5000:  # Minimum area threshold
                    
                    # Extract the color of this region from result image
                    region_crop = result_array[y:y2, x:x2]
                    region_color = np.median(region_crop.reshape(-1, 3), axis=0)
                    
                    rectangle_info = {
                        'bbox': (x, y, x2, y2),
                        'area': region_area,
                        'change_density': change_density,
                        'color': region_color,
                        'center': ((x + x2) // 2, (y + y2) // 2)
                    }
                    rectangles.append(rectangle_info)
    
    # Remove overlapping rectangles (keep larger ones)
    filtered_rectangles = []
    rectangles.sort(key=lambda r: r['area'], reverse=True)
    
    for rect in rectangles:
        x1, y1, x2, y2 = rect['bbox']
        overlap = False
        
        for existing in filtered_rectangles:
            ex1, ey1, ex2, ey2 = existing['bbox']
            
            # Check for significant overlap
            overlap_area = max(0, min(x2, ex2) - max(x1, ex1)) * max(0, min(y2, ey2) - max(y1, ey1))
            if overlap_area > rect['area'] * 0.5:  # 50% overlap threshold
                overlap = True
                break
        
        if not overlap:
            filtered_rectangles.append(rect)
    
    return filtered_rectangles


def is_in_lower_left(bbox, img_size):
    """
    Check if rectangle is positioned in the lower-left area of the image.
    """
    x1, y1, x2, y2 = bbox
    img_width, img_height = img_size
    
    center_x = (x1 + x2) // 2
    center_y = (y1 + y2) // 2
    
    # Lower-left area: left 60% horizontally, bottom 60% vertically
    in_left = center_x < img_width * 0.6
    in_lower = center_y > img_height * 0.4
    
    return in_left and in_lower


def calculate_color_distance(color1, color2):
    """Calculate Euclidean distance between two RGB colors."""
    return np.linalg.norm(np.array(color1) - np.array(color2))


def check_color_sampling(traj, env_info, task_info):
    """
    Main verifier function for color sampling task.
    Checks:
    1. Color was sampled from purple flower area
    2. Rectangular selection was created and filled
    3. Rectangle is positioned in lower-left area
    4. Filled rectangle color matches flower color
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
        "/home/ga/Desktop/color_sampled.jpg",
        "/home/ga/Desktop/color_sampled.png",
        "/home/ga/Desktop/color_sampled.jpeg",
        "/home/ga/Desktop/flower_sampled.jpg",
        "/home/ga/Desktop/flower_garden_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_garden.jpg",
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
        
        # Extract source color from flower area
        source_color = extract_source_color_from_flower(original_image)
        
        # Detect filled rectangles
        rectangles = detect_filled_rectangles(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Source flower color: RGB{tuple(source_color)}")
        feedback_parts.append(f"Rectangles detected: {len(rectangles)}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        best_match_score = 0
        best_rectangle = None
        
        # Check each rectangle for quality and position
        for rect in rectangles:
            if rect['area'] >= 5000:  # Minimum size requirement
                rect_color = rect['color']
                color_distance = calculate_color_distance(source_color, rect_color)
                
                # Good color match if distance <= 30 RGB units
                if color_distance <= 30:
                    match_score = max(0, 1 - color_distance / 100)
                    if match_score > best_match_score:
                        best_match_score = match_score
                        best_rectangle = rect
        
        if best_rectangle:
            rect_color = best_rectangle['color']
            color_distance = calculate_color_distance(source_color, rect_color)
            in_lower_left = is_in_lower_left(best_rectangle['bbox'], result_image.size)
            
            feedback_parts.append(f"Best rectangle: {best_rectangle['area']} pixels at {best_rectangle['center']}")
            feedback_parts.append(f"Rectangle color: RGB{tuple(rect_color.astype(int))}")
            feedback_parts.append(f"Color distance: {color_distance:.1f}")
            
            # Criteria 1: Color match achieved (≤30 RGB units distance)
            if color_distance <= 30:
                criteria_met += 1
            feedback_parts.append(f"Color match: {'✅' if color_distance <= 30 else '❌'}")
            
            # Criteria 2: Rectangle created (≥5000 pixels)
            if best_rectangle['area'] >= 5000:
                criteria_met += 1
            feedback_parts.append(f"Rectangle size adequate: {'✅' if best_rectangle['area'] >= 5000 else '❌'}")
            
            # Criteria 3: Correct position (lower-left area)
            if in_lower_left:
                criteria_met += 1
            feedback_parts.append(f"Position lower-left: {'✅' if in_lower_left else '❌'}")
            
            # Criteria 4: Good fill quality (uniform color)
            region_crop = np.array(result_image.crop(best_rectangle['bbox']))
            color_variance = np.var(region_crop.reshape(-1, 3), axis=0)
            uniform_fill = np.mean(color_variance) < 400  # Low variance indicates uniform fill
            if uniform_fill:
                criteria_met += 1
            feedback_parts.append(f"Uniform fill: {'✅' if uniform_fill else '❌'}")
            
        else:
            feedback_parts.append("❌ No suitable rectangles with matching colors found")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect color sampling!")
        elif passed:
            feedback_parts.append("✅ Good color sampling!")
        else:
            feedback_parts.append("❌ Color sampling needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color sampling verification: {e}")
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
    result = check_color_sampling([], {}, {})
    print(f"Test result: {result}")