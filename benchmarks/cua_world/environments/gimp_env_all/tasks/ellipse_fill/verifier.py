#!/usr/bin/env python3
"""
Verifier for GIMP ellipse fill task.
Checks if a red circular shape was created in the center area of the image.
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


def analyze_red_color_distribution(img):
    """
    Analyze red color distribution in the image.
    Returns percentage of pixels that are red and their spatial properties.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    total_pixels = img_array.shape[0] * img_array.shape[1]
    
    # Define red color ranges (more inclusive to handle anti-aliasing)
    red_mask = (
        (img_array[:, :, 0] >= 200) &  # High red
        (img_array[:, :, 1] <= 50) &   # Low green
        (img_array[:, :, 2] <= 50)     # Low blue
    )
    
    # Also check for darker red (for potential shadows or anti-aliasing)
    dark_red_mask = (
        (img_array[:, :, 0] >= 150) &  # Medium-high red
        (img_array[:, :, 1] <= 80) &   # Low-medium green
        (img_array[:, :, 2] <= 80) &   # Low-medium blue
        (img_array[:, :, 0] > img_array[:, :, 1] + 50) &  # Red significantly higher than green
        (img_array[:, :, 0] > img_array[:, :, 2] + 50)    # Red significantly higher than blue
    )
    
    # Combine red masks
    all_red_mask = red_mask | dark_red_mask
    red_pixels = np.sum(all_red_mask)
    red_percentage = (red_pixels / total_pixels) * 100
    
    return {
        'red_pixels': red_pixels,
        'red_percentage': red_percentage,
        'red_mask': all_red_mask,
        'total_pixels': total_pixels
    }


def analyze_circular_shape(red_mask):
    """
    Analyze if the red regions form a roughly circular shape.
    Uses connected components and shape analysis.
    """
    try:
        from scipy.ndimage import label, center_of_mass
        import cv2
        
        # Find connected components
        labeled_array, num_features = label(red_mask)
        
        if num_features == 0:
            return {
                'is_circular': False,
                'aspect_ratio': 0,
                'largest_component_area': 0,
                'center_position': None
            }
        
        # Find the largest component (should be our circle)
        largest_area = 0
        largest_component = None
        
        for i in range(1, num_features + 1):
            component_mask = (labeled_array == i)
            area = np.sum(component_mask)
            
            if area > largest_area:
                largest_area = area
                largest_component = component_mask
        
        if largest_component is None or largest_area < 100:  # Too small to be meaningful
            return {
                'is_circular': False,
                'aspect_ratio': 0,
                'largest_component_area': largest_area,
                'center_position': None
            }
        
        # Get center of mass for the largest component
        center = center_of_mass(largest_component)
        center_position = (int(center[1]), int(center[0]))  # Convert to (x, y)
        
        # Find contours using OpenCV for shape analysis
        component_uint8 = largest_component.astype(np.uint8) * 255
        contours, _ = cv2.findContours(component_uint8, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if len(contours) == 0:
            return {
                'is_circular': False,
                'aspect_ratio': 0,
                'largest_component_area': largest_area,
                'center_position': center_position
            }
        
        # Analyze the largest contour
        largest_contour = max(contours, key=cv2.contourArea)
        
        # Fit ellipse to the contour if possible
        if len(largest_contour) >= 5:  # Need at least 5 points for ellipse fitting
            ellipse = cv2.fitEllipse(largest_contour)
            (center_cv, axes, angle) = ellipse
            
            # Calculate aspect ratio (how close to circular)
            aspect_ratio = min(axes) / max(axes) if max(axes) > 0 else 0
            
            return {
                'is_circular': aspect_ratio >= 0.7,  # Reasonably circular
                'aspect_ratio': aspect_ratio,
                'largest_component_area': largest_area,
                'center_position': center_position,
                'ellipse_center': center_cv,
                'ellipse_axes': axes
            }
        else:
            # Fallback: use bounding box analysis
            y_coords, x_coords = np.where(largest_component)
            if len(x_coords) > 0:
                width = np.max(x_coords) - np.min(x_coords)
                height = np.max(y_coords) - np.min(y_coords)
                aspect_ratio = min(width, height) / max(width, height) if max(width, height) > 0 else 0
                
                return {
                    'is_circular': aspect_ratio >= 0.7,
                    'aspect_ratio': aspect_ratio,
                    'largest_component_area': largest_area,
                    'center_position': center_position
                }
            
    except ImportError:
        logging.warning("Advanced shape analysis libraries not available, using fallback")
        # Fallback shape analysis without scipy/cv2
        y_coords, x_coords = np.where(red_mask)
        if len(x_coords) == 0:
            return {
                'is_circular': False,
                'aspect_ratio': 0,
                'largest_component_area': 0,
                'center_position': None
            }
        
        # Simple bounding box analysis
        width = np.max(x_coords) - np.min(x_coords)
        height = np.max(y_coords) - np.min(y_coords)
        aspect_ratio = min(width, height) / max(width, height) if max(width, height) > 0 else 0
        
        center_x = (np.min(x_coords) + np.max(x_coords)) // 2
        center_y = (np.min(y_coords) + np.max(y_coords)) // 2
        
        return {
            'is_circular': aspect_ratio >= 0.7,
            'aspect_ratio': aspect_ratio,
            'largest_component_area': len(x_coords),
            'center_position': (center_x, center_y)
        }
    
    # Default fallback
    return {
        'is_circular': False,
        'aspect_ratio': 0,
        'largest_component_area': 0,
        'center_position': None
    }


def check_center_positioning(center_position, img_size):
    """
    Check if the detected shape is positioned in the central area of the image.
    """
    if center_position is None:
        return False
    
    width, height = img_size
    center_x, center_y = center_position
    
    # Define central area (middle 60% of both dimensions)
    center_bounds = {
        'x_min': width * 0.2,
        'x_max': width * 0.8,
        'y_min': height * 0.2,
        'y_max': height * 0.8
    }
    
    is_centered = (
        center_bounds['x_min'] <= center_x <= center_bounds['x_max'] and
        center_bounds['y_min'] <= center_y <= center_bounds['y_max']
    )
    
    return is_centered


def check_ellipse_fill(traj, env_info, task_info):
    """
    Main verifier function for ellipse fill task.
    Checks:
    1. Red color is present in significant amount (5-40% of image)
    2. Red region forms a reasonably circular shape (aspect ratio 0.7-1.4)
    3. Circle is positioned in central area of image
    4. Fill appears complete and solid
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
        "/home/ga/Desktop/red_circle.png",
        "/home/ga/Desktop/red_circle.jpg", 
        "/home/ga/Desktop/red_circle.jpeg",
        "/home/ga/Desktop/circle.png",
        "/home/ga/Desktop/ellipse.png",
        "/home/ga/Desktop/blank_canvas_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/blank_canvas.jpg",
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
        
        # Analyze red color distribution
        color_analysis = analyze_red_color_distribution(result_image)
        
        # Analyze shape characteristics
        shape_analysis = analyze_circular_shape(color_analysis['red_mask'])
        
        # Check center positioning
        correctly_positioned = check_center_positioning(shape_analysis['center_position'], result_image.size)
        
        # Check if image was modified (simple check)
        images_different = not np.array_equal(np.array(original_image.convert('RGB')), np.array(result_image.convert('RGB')))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Red pixels: {color_analysis['red_percentage']:.1f}%")
        feedback_parts.append(f"Largest component area: {shape_analysis['largest_component_area']}")
        if shape_analysis['center_position']:
            feedback_parts.append(f"Shape center: {shape_analysis['center_position']}")
        feedback_parts.append(f"Aspect ratio: {shape_analysis['aspect_ratio']:.2f}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant red color present (5-40% of image area)
        red_amount_good = 5 <= color_analysis['red_percentage'] <= 40
        if red_amount_good:
            criteria_met += 1
        feedback_parts.append(f"Red color present (5-40%): {'✅' if red_amount_good else '❌'}")
        
        # 2. Shape is reasonably circular
        if shape_analysis['is_circular']:
            criteria_met += 1
        feedback_parts.append(f"Circular shape (AR≥0.7): {'✅' if shape_analysis['is_circular'] else '❌'}")
        
        # 3. Positioned in center area
        if correctly_positioned:
            criteria_met += 1
        feedback_parts.append(f"Center positioned: {'✅' if correctly_positioned else '❌'}")
        
        # 4. Image was modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect red circle created!")
        elif passed:
            feedback_parts.append("✅ Good red circle!")
        else:
            feedback_parts.append("❌ Circle creation needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in ellipse fill verification: {e}")
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
    result = check_ellipse_fill([], {}, {})
    print(f"Test result: {result}")