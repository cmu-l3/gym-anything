#!/usr/bin/env python3
"""
Verifier for GIMP new image creation task.
Checks if a new blank image was created with 640x480 dimensions and white background.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")

logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def check_image_dimensions(img, target_width=640, target_height=480, tolerance=0):
    """Check if image has exact target dimensions."""
    width, height = img.size
    
    width_correct = width == target_width
    height_correct = height == target_height
    
    return width_correct and height_correct, (width, height)


def analyze_background_color(img):
    """
    Analyze if the image has a uniform white background.
    Returns statistics about the background color.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Calculate color statistics
    mean_color = np.mean(img_array, axis=(0,1))  # Average RGB values
    std_color = np.std(img_array, axis=(0,1))    # Color variation
    overall_std = np.std(img_array)              # Overall variation
    
    # Check if colors are close to white (255, 255, 255)
    white_threshold = 250  # RGB values should be close to 255
    is_near_white = np.all(mean_color >= white_threshold)
    
    # Check uniformity (low standard deviation indicates solid color)
    is_uniform = overall_std < 5  # Very low variation
    
    # Count pixels that are very close to white
    white_pixels = np.sum(np.all(img_array >= white_threshold, axis=2))
    total_pixels = img_array.shape[0] * img_array.shape[1]
    white_percentage = (white_pixels / total_pixels) * 100
    
    return {
        'mean_color': mean_color,
        'std_color': std_color,
        'overall_std': overall_std,
        'is_near_white': is_near_white,
        'is_uniform': is_uniform,
        'white_percentage': white_percentage,
        'white_pixels': white_pixels,
        'total_pixels': total_pixels
    }


def check_clean_canvas(img):
    """
    Check if the image is a clean, blank canvas without artifacts or content.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Check for edge artifacts by examining border pixels
    top_edge = img_array[0, :, :]
    bottom_edge = img_array[-1, :, :]
    left_edge = img_array[:, 0, :]
    right_edge = img_array[:, -1, :]
    
    # Calculate variation in edges (should be minimal for clean canvas)
    edge_std = np.std([top_edge, bottom_edge, left_edge, right_edge])
    
    # Check center region for any unexpected patterns
    h, w = img_array.shape[:2]
    center_region = img_array[h//4:3*h//4, w//4:3*w//4, :]
    center_std = np.std(center_region)
    
    # Look for any significant gradients or patterns
    # Clean canvas should have minimal variation throughout
    has_artifacts = edge_std > 3 or center_std > 3
    
    return {
        'edge_std': edge_std,
        'center_std': center_std,
        'has_artifacts': has_artifacts,
        'is_clean': not has_artifacts
    }


def check_new_image(traj, env_info, task_info):
    """
    Main verifier function for new image creation task.
    Checks:
    1. Image dimensions are exactly 640x480 pixels
    2. Background is uniform white color
    3. Canvas is clean without artifacts or content
    4. Image was properly exported
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in env_info"
        }
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Try different possible result file names
        possible_results = [
            "/home/ga/Desktop/new_blank_image.png",
            "/home/ga/Desktop/new_blank_image.jpg", 
            "/home/ga/Desktop/new_blank_image.jpeg",
            "/home/ga/Desktop/blank_image.png",
            "/home/ga/Desktop/new_image.png",
            "/home/ga/Desktop/new_blank_image.xcf"  # GIMP native format fallback
        ]
        
        # Define host path for result
        host_result = temp_path / "result_image.png"
        
        # Try to copy result image from container
        result_found = False
        result_container_path = None
        for result_path in possible_results:
            success, error = copy_file_from_container(copy_from_env, result_path, host_result)
            if success:
                result_found = True
                result_container_path = result_path
                logging.debug(f"Found result image at: {result_path}")
                break
        
        if not result_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result image. Tried: {[Path(p).name for p in possible_results]}"
            }
        
        try:
            # Load image from copied file
            result_image = Image.open(host_result)
            
            logging.debug(f"Found result image at: {result_container_path}")
            
            # Check dimensions (exact match required)
            dimensions_correct, actual_dims = check_image_dimensions(result_image, 640, 480, tolerance=0)
            
            # Analyze background color
            color_analysis = analyze_background_color(result_image)
            
            # Check canvas cleanliness
            canvas_analysis = check_clean_canvas(result_image)
            
            # Verify image format and properties
            format_valid = result_image.format in ['PNG', 'JPEG', 'TIFF'] or result_image.format is not None
            
            feedback_parts = []
            feedback_parts.append(f"Result size: {result_image.size}")
            feedback_parts.append(f"Target size: (640, 480)")
            feedback_parts.append(f"Format: {result_image.format}")
            feedback_parts.append(f"Dimensions correct: {'✅' if dimensions_correct else '❌'}")
            feedback_parts.append(f"Average color: RGB({color_analysis['mean_color'][0]:.0f}, {color_analysis['mean_color'][1]:.0f}, {color_analysis['mean_color'][2]:.0f})")
            feedback_parts.append(f"White background: {'✅' if color_analysis['is_near_white'] else '❌'}")
            feedback_parts.append(f"Uniform color: {'✅' if color_analysis['is_uniform'] else '❌'}")
            feedback_parts.append(f"White pixels: {color_analysis['white_percentage']:.1f}%")
            feedback_parts.append(f"Clean canvas: {'✅' if canvas_analysis['is_clean'] else '❌'}")
            feedback_parts.append(f"Valid format: {'✅' if format_valid else '❌'}")
            
            # Calculate success based on multiple criteria
            criteria_met = 0
            total_criteria = 4
            
            if dimensions_correct:
                criteria_met += 1
            if color_analysis['is_near_white'] and color_analysis['white_percentage'] > 95:
                criteria_met += 1 
            if color_analysis['is_uniform']:
                criteria_met += 1
            if canvas_analysis['is_clean']:
                criteria_met += 1
            
            # Score based on criteria met
            score = int((criteria_met / total_criteria) * 100)
            passed = score >= 75  # Need at least 3/4 criteria
            
            if passed and score >= 95:
                feedback_parts.append("🎉 Perfect new image creation!")
            elif passed:
                feedback_parts.append("✅ Good new image creation!")
            else:
                feedback_parts.append("❌ New image creation needs improvement")
                
            return {
                "passed": passed,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        except Exception as e:
            logging.error(f"Error in new image verification: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: {str(e)}"
            }


if __name__ == "__main__":
    # Test the verifier
    result = check_new_image([], {}, {})
    print(f"Test result: {result}")