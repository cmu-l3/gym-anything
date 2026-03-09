#!/usr/bin/env python3
"""
Verifier for GIMP circular selection and fill task.
Checks if a circular region was created and filled with a bright color.
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


def calculate_circularity(region_mask):
    """
    Calculate how circular a region is using the circularity formula.
    Returns a value between 0 and 1, where 1 is a perfect circle.
    """
    area = np.sum(region_mask)
    if area == 0:
        return 0.0
    
    # Calculate perimeter using edge detection
    try:
        # Find the boundary of the region
        from scipy.ndimage import binary_erosion
        eroded = binary_erosion(region_mask)
        boundary = region_mask ^ eroded
        perimeter = np.sum(boundary)
    except ImportError:
        # Fallback: approximate perimeter using a simple edge count
        shifted_up = np.roll(region_mask, -1, axis=0)
        shifted_down = np.roll(region_mask, 1, axis=0)
        shifted_left = np.roll(region_mask, -1, axis=1)
        shifted_right = np.roll(region_mask, 1, axis=1)
        
        edges = ((region_mask != shifted_up) | (region_mask != shifted_down) | 
                (region_mask != shifted_left) | (region_mask != shifted_right))
        perimeter = np.sum(edges & region_mask)
    
    if perimeter == 0:
        return 0.0
    
    # Circularity formula: 4π * area / perimeter²
    circularity = (4 * np.pi * area) / (perimeter ** 2)
    return min(circularity, 1.0)  # Cap at 1.0 for measurement noise


def check_center_position(region_centroid, image_shape):
    """
    Check if a region is roughly centered in the image.
    Returns True if the centroid is within the central 60% of the image.
    """
    img_center = (image_shape[1] // 2, image_shape[0] // 2)
    distance = np.sqrt((region_centroid[0] - img_center[0])**2 + 
                      (region_centroid[1] - img_center[1])**2)
    
    # Allow up to 30% of image diagonal as acceptable deviation
    max_deviation = 0.3 * np.sqrt(image_shape[0]**2 + image_shape[1]**2)
    return distance <= max_deviation


def detect_circular_fill(original_img, result_img):
    """
    Detect and analyze circular filled regions in the result image.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB arrays
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    delta = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    magnitude = np.mean(delta, axis=2)
    
    # Threshold to find significantly changed pixels (likely the filled region)
    threshold = max(np.percentile(magnitude, 85), 20)
    changed_pixels = magnitude > threshold
    
    # Find connected components (regions) of changed pixels
    try:
        from scipy.ndimage import label
        labeled, num_features = label(changed_pixels)
        
        if num_features == 0:
            return None, "No filled regions detected"
        
        # Analyze each region to find the most circular one
        best_region = None
        best_score = 0
        
        for region_id in range(1, num_features + 1):
            region_mask = (labeled == region_id)
            area = np.sum(region_mask)
            
            # Skip very small regions (likely noise)
            if area < 200:  # Minimum area threshold
                continue
            
            # Calculate region properties
            circularity = calculate_circularity(region_mask)
            
            # Calculate centroid
            y_coords, x_coords = np.where(region_mask)
            if len(y_coords) == 0:
                continue
            centroid = (np.mean(x_coords), np.mean(y_coords))
            
            # Check if it's centered
            is_centered = check_center_position(centroid, orig_array.shape)
            
            # Calculate total area ratio
            total_pixels = orig_array.shape[0] * orig_array.shape[1]
            area_ratio = area / total_pixels
            
            # Score this region (higher is better)
            score = circularity * (2 if is_centered else 1) * min(area_ratio * 10, 1)
            
            if score > best_score:
                best_score = score
                best_region = {
                    'mask': region_mask,
                    'area': area,
                    'area_ratio': area_ratio,
                    'circularity': circularity,
                    'centroid': centroid,
                    'is_centered': is_centered,
                    'score': score
                }
        
        return best_region, "Analysis complete"
        
    except ImportError:
        # Fallback without scipy: use simple grid-based detection
        height, width = changed_pixels.shape
        center_x, center_y = width // 2, height // 2
        
        # Look for circular pattern around center
        max_radius = min(width, height) // 3
        
        for radius in range(max_radius, 20, -5):  # Test different radii
            circle_mask = np.zeros_like(changed_pixels, dtype=bool)
            y, x = np.ogrid[:height, :width]
            circle_area = (x - center_x)**2 + (y - center_y)**2 <= radius**2
            
            # Check overlap with changed pixels
            overlap = np.sum(circle_area & changed_pixels)
            circle_total = np.sum(circle_area)
            
            if circle_total > 0 and overlap / circle_total > 0.3:  # At least 30% filled
                area_ratio = circle_total / (width * height)
                return {
                    'mask': circle_area & changed_pixels,
                    'area': overlap,
                    'area_ratio': area_ratio,
                    'circularity': 0.8,  # Assume decent circularity for grid method
                    'centroid': (center_x, center_y),
                    'is_centered': True,
                    'score': 0.7
                }, "Grid-based detection"
        
        return None, "No circular region detected with fallback method"


def analyze_fill_color(result_img, region_mask):
    """
    Analyze the color of the filled region to ensure it's bright/distinctive.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    img_array = np.array(result_img)
    
    # Extract colors from the filled region
    region_colors = img_array[region_mask]
    
    if len(region_colors) == 0:
        return False, "No pixels in region"
    
    # Calculate average color
    avg_color = np.mean(region_colors, axis=0)
    
    # Check if it's a bright/saturated color
    # Criteria: either high brightness OR high saturation
    brightness = np.mean(avg_color)
    max_channel = np.max(avg_color)
    min_channel = np.min(avg_color)
    saturation = (max_channel - min_channel) / max(max_channel, 1)
    
    is_bright = brightness > 150  # Bright color
    is_saturated = saturation > 0.3  # Saturated color
    
    return is_bright or is_saturated, f"Brightness: {brightness:.1f}, Saturation: {saturation:.2f}"


def check_circular_fill(traj, env_info, task_info):
    """
    Main verifier function for circular fill task.
    Checks:
    1. A circular region was created and filled
    2. The region is appropriately sized and positioned
    3. The fill color is bright/distinctive
    4. Image was meaningfully modified
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
        "/home/ga/Desktop/circular_fill.png",
        "/home/ga/Desktop/circular_fill.jpg",
        "/home/ga/Desktop/circular_fill.jpeg",
        "/home/ga/Desktop/circle_test_image_edited.jpg",
        "/home/ga/Desktop/circle_filled.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/circle_test_image.jpg",
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
        
        # Detect circular filled region
        region_data, analysis_msg = detect_circular_fill(original_image, result_image)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image.convert('RGB')), 
                                            np.array(result_image.convert('RGB')))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Analysis: {analysis_msg}")
        
        if region_data is None:
            feedback_parts.append("❌ No circular filled region detected")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Analyze the detected region
        area_ratio = region_data['area_ratio']
        circularity = region_data['circularity']
        is_centered = region_data['is_centered']
        
        # Analyze fill color
        color_good, color_info = analyze_fill_color(result_image, region_data['mask'])
        
        feedback_parts.append(f"Region area: {region_data['area']} pixels ({area_ratio:.1%})")
        feedback_parts.append(f"Circularity: {circularity:.2f}")
        feedback_parts.append(f"Centroid: ({region_data['centroid'][0]:.0f}, {region_data['centroid'][1]:.0f})")
        feedback_parts.append(f"Color info: {color_info}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 6
        
        # 1. Circular region detected
        criteria_met += 1
        feedback_parts.append("✅ Circular region detected")
        
        # 2. Appropriate size (15-65% of image area)
        size_appropriate = 0.15 <= area_ratio <= 0.65
        if size_appropriate:
            criteria_met += 1
        feedback_parts.append(f"Appropriate size: {'✅' if size_appropriate else '❌'}")
        
        # 3. Reasonably circular (circularity >= 0.6)
        circular_enough = circularity >= 0.6
        if circular_enough:
            criteria_met += 1
        feedback_parts.append(f"Reasonably circular: {'✅' if circular_enough else '❌'}")
        
        # 4. Roughly centered
        if is_centered:
            criteria_met += 1
        feedback_parts.append(f"Roughly centered: {'✅' if is_centered else '❌'}")
        
        # 5. Bright/distinctive color
        if color_good:
            criteria_met += 1
        feedback_parts.append(f"Good fill color: {'✅' if color_good else '❌'}")
        
        # 6. Image modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 5/6 criteria (83%) but we'll use 75% threshold
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect circular fill!")
        elif passed:
            feedback_parts.append("✅ Good circular fill!")
        else:
            feedback_parts.append("❌ Circular fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in circular fill verification: {e}")
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
    result = check_circular_fill([], {}, {})
    print(f"Test result: {result}")