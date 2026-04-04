"""
Verifier for green background task.
Checks that the background was filled with green while preserving the object.
"""

import os
import sys
import tempfile
import logging
from pathlib import Path
from PIL import Image
import numpy as np

# Set up logging
logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def analyze_dominant_background_color(img, sample_regions=None):
    """
    Analyze the dominant background color by sampling edge regions.
    Returns RGB tuple of the most common color in background areas.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    
    # Default sample regions if not provided (edges of image)
    if sample_regions is None:
        sample_regions = [
            (0, 0, width, 20),  # Top edge
            (0, height-20, width, height),  # Bottom edge  
            (0, 0, 20, height),  # Left edge
            (width-20, 0, width, height),  # Right edge
        ]
    
    # Collect background pixels from sample regions
    background_pixels = []
    for x1, y1, x2, y2 in sample_regions:
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(width, x2), min(height, y2)
        region = img_array[y1:y2, x1:x2]
        background_pixels.extend(region.reshape(-1, 3))
    
    if not background_pixels:
        return (0, 0, 0)  # Default to black if no pixels
    
    background_pixels = np.array(background_pixels)
    
    # Find most common color (simple approach: round to nearest 10 and find mode)
    rounded_pixels = (background_pixels // 10) * 10
    unique_colors, counts = np.unique(rounded_pixels, axis=0, return_counts=True)
    dominant_color = unique_colors[np.argmax(counts)]
    
    return tuple(dominant_color)


def is_green_color(rgb, tolerance=50):
    """
    Check if an RGB color is predominantly green.
    Green should be highest component, and significantly higher than red/blue.
    """
    r, g, b = rgb
    
    # Green should be the dominant component
    if g < max(r, b):
        return False
    
    # Green should be significantly higher than red and blue
    if g < r + tolerance or g < b + tolerance:
        return False
    
    # Green should be reasonably high (not just dark)
    if g < 80:
        return False
    
    return True


def check_object_preservation(original_img, result_img, background_tolerance=30):
    """
    Check if the object is preserved by comparing non-background regions.
    Returns similarity score for object areas.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Create a mask for likely object pixels (non-background)
    # Assume background is roughly uniform, so find pixels that differ significantly from corners
    height, width = orig_array.shape[:2]
    
    # Sample corner colors to estimate background
    corner_colors = [
        orig_array[0, 0],  # Top-left
        orig_array[0, width-1],  # Top-right  
        orig_array[height-1, 0],  # Bottom-left
        orig_array[height-1, width-1],  # Bottom-right
    ]
    avg_bg_color = np.mean(corner_colors, axis=0)
    
    # Create object mask: pixels that are significantly different from background
    color_diff = np.linalg.norm(orig_array - avg_bg_color, axis=2)
    object_mask = color_diff > background_tolerance
    
    if not np.any(object_mask):
        return 1.0  # No object detected, so it's "preserved" trivially
    
    # Compare object regions between original and result
    orig_object_pixels = orig_array[object_mask]
    result_object_pixels = result_array[object_mask]
    
    # Calculate pixel-wise similarity
    pixel_diffs = np.linalg.norm(orig_object_pixels - result_object_pixels, axis=1)
    similarity = np.mean(pixel_diffs < background_tolerance)
    
    return similarity


def check_green_background(traj, env_info, task_info):
    """
    Main verifier function for green background task.
    
    Args:
        traj: Trajectory data with episode information
        env_info: Environment information including episode directory and copy utilities
        task_info: Task information
        
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    
    # Get episode directory and copy utilities
    episode_dir = env_info.get("episode_dir")
    copy_from_env = env_info.get("copy_from_env")
    
    if not episode_dir:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No episode directory found"
        }
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy utilities available"
        }
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container paths
        container_original = "/home/ga/Desktop/white_background_with_object.png"
        container_result = "/home/ga/Desktop/green_background_with_object.png"
        
        # Define host paths
        host_original = temp_path / "original.png"
        host_result = temp_path / "result.png"
        
        # Try to copy original image from container
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original image: {error}"
            }
        
        # Try to copy result image from container
        success, error = copy_file_from_container(copy_from_env, container_result, host_result)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result image: {error}. Make sure the image was exported as green_background_with_object.png"
            }
        
        try:
            # Load images from copied files
            original_image = Image.open(host_original)
            result_image = Image.open(host_result)
            
            # Analyze background color in result
            bg_color = analyze_dominant_background_color(result_image)
            is_bg_green = is_green_color(bg_color)
            
            # Check object preservation
            object_similarity = check_object_preservation(original_image, result_image)
            object_preserved = object_similarity > 0.7  # 70% similarity threshold
            
            feedback_parts = []
            feedback_parts.append(f"Original size: {original_image.size}")
            feedback_parts.append(f"Result size: {result_image.size}")
            feedback_parts.append(f"Background color (RGB): {bg_color}")
            feedback_parts.append(f"Is background green: {'✅' if is_bg_green else '❌'}")
            feedback_parts.append(f"Object preserved: {'✅' if object_preserved else '❌'} ({object_similarity:.2f})")
            
            # Both conditions must be met
            success = is_bg_green and object_preserved
            
            if success:
                feedback_parts.append("🎉 Background successfully filled with green and object preserved!")
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                if not is_bg_green:
                    feedback_parts.append("❌ Background was not filled with green color")
                if not object_preserved:
                    feedback_parts.append("❌ Object was not preserved correctly")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error during verification: {str(e)}"
            }
