#!/usr/bin/env python3
"""
Verifier for GIMP draw line task.
Checks if a straight red line was drawn on the canvas using the pencil tool.
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


def detect_red_pixels(img):
    """
    Detect bright red pixels in the image.
    Returns mask of pixels that are bright red.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Define red color range (bright red)
    red_mask = (
        (img_array[:, :, 0] >= 240) &  # Red channel high (240-255)
        (img_array[:, :, 1] <= 30) &    # Green channel low (0-30)
        (img_array[:, :, 2] <= 30)      # Blue channel low (0-30)
    )
    
    return red_mask, np.sum(red_mask)


def analyze_line_geometry(red_mask):
    """
    Analyze the geometry of detected red pixels to determine if they form a line.
    Returns linearity metrics and measurements.
    """
    # Get coordinates of red pixels
    red_coords = np.argwhere(red_mask)
    
    if len(red_coords) < 10:  # Need minimum pixels for analysis
        return {
            'has_enough_pixels': False,
            'pixel_count': len(red_coords),
            'aspect_ratio': 0,
            'length': 0,
            'straightness_score': 0
        }
    
    # Get bounding box
    y_coords, x_coords = red_coords[:, 0], red_coords[:, 1]
    y_min, y_max = y_coords.min(), y_coords.max()
    x_min, x_max = x_coords.min(), x_coords.max()
    
    height = y_max - y_min + 1
    width = x_max - x_min + 1
    
    # Calculate aspect ratio (length/width - should be high for lines)
    aspect_ratio = max(height, width) / max(min(height, width), 1)
    
    # Calculate actual length (diagonal distance)
    length = max(height, width)
    
    # Analyze straightness using line fitting
    straightness_score = 0
    try:
        # Try to import sklearn for line fitting
        from sklearn.linear_model import RANSACRegressor
        
        # Fit line to coordinates
        X = x_coords.reshape(-1, 1)
        y = y_coords
        
        ransac = RANSACRegressor(random_state=42)
        ransac.fit(X, y)
        
        # Calculate how well points fit the line
        y_pred = ransac.predict(X)
        deviations = np.abs(y - y_pred)
        mean_deviation = np.mean(deviations)
        
        # Straightness score: lower deviation = higher score
        straightness_score = max(0, 10 - mean_deviation)  # Scale to 0-10
        
    except ImportError:
        # Fallback: use aspect ratio as proxy for straightness
        straightness_score = min(10, aspect_ratio / 2)
    
    return {
        'has_enough_pixels': True,
        'pixel_count': len(red_coords),
        'aspect_ratio': aspect_ratio,
        'length': length,
        'straightness_score': straightness_score,
        'bbox_width': width,
        'bbox_height': height
    }


def check_line_drawing(traj, env_info, task_info):
    """
    Main verifier function for line drawing task.
    Checks:
    1. Red pixels are present (at least 50-100 pixels)
    2. Red pixels form a linear pattern (high aspect ratio)
    3. Line is sufficiently long (≥100 pixels)
    4. Line is reasonably straight (low deviation from best-fit line)
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
        "/home/ga/Desktop/line_drawing.png",
        "/home/ga/Desktop/line_drawing.jpg",
        "/home/ga/Desktop/line_drawing.jpeg",
        "/home/ga/Desktop/blank_canvas_edited.png",
        "/home/ga/Desktop/canvas_with_line.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/blank_canvas.png",
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
        
        # Detect red pixels in result image
        red_mask, red_pixel_count = detect_red_pixels(result_image)
        
        # Analyze line geometry
        geometry = analyze_line_geometry(red_mask)
        
        # Check if images are different (something was drawn)
        images_different = not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Red pixels detected: {red_pixel_count}")
        if geometry['has_enough_pixels']:
            feedback_parts.append(f"Line length: {geometry['length']} pixels")
            feedback_parts.append(f"Aspect ratio: {geometry['aspect_ratio']:.1f}")
            feedback_parts.append(f"Straightness score: {geometry['straightness_score']:.1f}/10")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Sufficient red pixels (at least 50)
        enough_pixels = red_pixel_count >= 50
        if enough_pixels:
            criteria_met += 1
        feedback_parts.append(f"Enough red pixels (≥50): {'✅' if enough_pixels else '❌'}")
        
        # 2. Linear pattern (aspect ratio ≥5:1)
        linear_pattern = geometry.get('aspect_ratio', 0) >= 5
        if linear_pattern:
            criteria_met += 1
        feedback_parts.append(f"Linear pattern (aspect ≥5:1): {'✅' if linear_pattern else '❌'}")
        
        # 3. Sufficient length (≥100 pixels)
        sufficient_length = geometry.get('length', 0) >= 100
        if sufficient_length:
            criteria_met += 1
        feedback_parts.append(f"Sufficient length (≥100px): {'✅' if sufficient_length else '❌'}")
        
        # 4. Reasonably straight (straightness score ≥5)
        reasonably_straight = geometry.get('straightness_score', 0) >= 5
        if reasonably_straight:
            criteria_met += 1
        feedback_parts.append(f"Reasonably straight (score≥5): {'✅' if reasonably_straight else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent straight line drawing!")
        elif passed:
            feedback_parts.append("✅ Good line drawing!")
        else:
            feedback_parts.append("❌ Line drawing needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in line drawing verification: {e}")
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
    result = check_line_drawing([], {}, {})
    print(f"Test result: {result}")