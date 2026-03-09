#!/usr/bin/env python3
"""
Verifier for GIMP rectangle clear task.
Checks if the top-left quarter was selected and cleared to white/background color.
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


def analyze_quadrants(img):
    """
    Divide image into four equal quadrants and analyze each region.
    Returns statistics for each quadrant.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    width, height = img.size
    mid_x, mid_y = width // 2, height // 2
    
    # Define quadrant boundaries
    quadrants = {
        'top_left': (0, 0, mid_x, mid_y),
        'top_right': (mid_x, 0, width, mid_y),
        'bottom_left': (0, mid_y, mid_x, height),
        'bottom_right': (mid_x, mid_y, width, height)
    }
    
    results = {}
    for name, bbox in quadrants.items():
        quad_img = img.crop(bbox)
        quad_array = np.array(quad_img)
        
        # Calculate statistics for this quadrant
        mean_brightness = np.mean(quad_array)
        std_dev = np.std(quad_array)
        
        # Calculate uniformity (low std_dev indicates uniform color)
        uniformity = 1.0 - (std_dev / 255.0)
        
        # Count white/light pixels (>240 in all channels)
        light_pixels = np.sum(np.all(quad_array > 240, axis=2))
        total_pixels = quad_array.shape[0] * quad_array.shape[1]
        light_percentage = (light_pixels / total_pixels) * 100
        
        results[name] = {
            'mean_brightness': mean_brightness,
            'std_dev': std_dev,
            'uniformity': uniformity,
            'light_percentage': light_percentage,
            'area': total_pixels
        }
    
    return results


def detect_cleared_region(original_img, result_img):
    """
    Compare original and result images to detect cleared regions.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Analyze quadrants in both images
    original_quads = analyze_quadrants(original_img)
    result_quads = analyze_quadrants(result_img)
    
    # Compare quadrants to detect changes
    quadrant_changes = {}
    for quad_name in ['top_left', 'top_right', 'bottom_left', 'bottom_right']:
        orig = original_quads[quad_name]
        result = result_quads[quad_name]
        
        # Calculate change metrics
        brightness_change = result['mean_brightness'] - orig['mean_brightness']
        uniformity_change = result['uniformity'] - orig['uniformity']
        
        # Determine if this quadrant was cleared (became brighter and more uniform)
        cleared = (brightness_change > 50 and  # Significantly brighter
                  result['uniformity'] > 0.9 and  # Very uniform (solid color)
                  result['mean_brightness'] > 240)  # Very bright (white-ish)
        
        quadrant_changes[quad_name] = {
            'brightness_change': brightness_change,
            'uniformity_change': uniformity_change,
            'cleared': cleared,
            'final_brightness': result['mean_brightness'],
            'final_uniformity': result['uniformity']
        }
    
    return quadrant_changes


def check_rectangle_clear(traj, env_info, task_info):
    """
    Main verifier function for rectangle clear task.
    Checks:
    1. Top-left quadrant is cleared (uniform and bright)
    2. Other quadrants remain largely unchanged
    3. Cleared region is appropriately sized (roughly 25% of image)
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
        "/home/ga/Desktop/cleared_quarter.png",
        "/home/ga/Desktop/cleared_quarter.jpg", 
        "/home/ga/Desktop/cleared_quarter.jpeg",
        "/home/ga/Desktop/landscape_cleared.png",
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
        
        # Detect cleared regions by comparing quadrants
        quadrant_changes = detect_cleared_region(original_image, result_image)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image.convert('RGB')), 
                                             np.array(result_image.convert('RGB')))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        
        # Analyze each quadrant
        for quad_name, changes in quadrant_changes.items():
            feedback_parts.append(f"{quad_name}: brightness={changes['final_brightness']:.1f}, uniform={changes['final_uniformity']:.2f}, cleared={'✅' if changes['cleared'] else '❌'}")
        
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Top-left quadrant is cleared
        top_left_cleared = quadrant_changes['top_left']['cleared']
        if top_left_cleared:
            criteria_met += 1
        feedback_parts.append(f"Top-left cleared: {'✅' if top_left_cleared else '❌'}")
        
        # 2. Top-left is in correct spatial location (inherently true if detected)
        correct_location = top_left_cleared  # If top-left is cleared, location is correct
        if correct_location:
            criteria_met += 1
        feedback_parts.append(f"Correct spatial location: {'✅' if correct_location else '❌'}")
        
        # 3. Other quadrants are preserved (not cleared)
        other_quads_preserved = not any(quadrant_changes[q]['cleared'] 
                                      for q in ['top_right', 'bottom_left', 'bottom_right'])
        if other_quads_preserved:
            criteria_met += 1
        feedback_parts.append(f"Other areas preserved: {'✅' if other_quads_preserved else '❌'}")
        
        # 4. Appropriate size (cleared region is roughly 25% of image)
        cleared_quadrants = sum(1 for changes in quadrant_changes.values() if changes['cleared'])
        appropriate_size = cleared_quadrants == 1  # Exactly one quadrant cleared
        if appropriate_size:
            criteria_met += 1
        feedback_parts.append(f"Appropriate size (1 quadrant): {'✅' if appropriate_size else '❌'}")
        
        # 5. Image was meaningfully modified
        if images_different:
            criteria_met += 1
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (equivalent to 80%, but we'll use 75% threshold)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rectangle clear!")
        elif passed:
            feedback_parts.append("✅ Good rectangle clear!")
        else:
            feedback_parts.append("❌ Rectangle clear needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rectangle clear verification: {e}")
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
    result = check_rectangle_clear([], {}, {})
    print(f"Test result: {result}")