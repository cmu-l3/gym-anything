#!/usr/bin/env python3
"""
Verifier for GIMP fuzzy select and fill task.
Checks if uniform background was selected and filled with new color.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
from collections import Counter

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def detect_background_color(img_array, tolerance=30):
    """
    Automatically detect the dominant edge/corner color as background.
    Uses edge sampling to identify the most common background color.
    """
    h, w = img_array.shape[:2]
    
    # Sample corners and edges more comprehensively
    edge_pixels = []
    
    # Sample all four corners (10x10 patches)
    corners = [
        img_array[0:10, 0:10],      # Top-left
        img_array[0:10, -10:],      # Top-right
        img_array[-10:, 0:10],      # Bottom-left
        img_array[-10:, -10:]       # Bottom-right
    ]
    
    for corner in corners:
        edge_pixels.extend(corner.reshape(-1, 3))
    
    # Sample edges (every 5th pixel to reduce computation)
    edge_pixels.extend(img_array[0, ::5].reshape(-1, 3))    # Top edge
    edge_pixels.extend(img_array[-1, ::5].reshape(-1, 3))   # Bottom edge
    edge_pixels.extend(img_array[::5, 0].reshape(-1, 3))    # Left edge
    edge_pixels.extend(img_array[::5, -1].reshape(-1, 3))   # Right edge
    
    # Convert to tuples for counting
    colors = [tuple(pixel) for pixel in edge_pixels]
    
    # Find most common color in edges (likely background)
    color_counts = Counter(colors)
    most_common_color = color_counts.most_common(1)[0][0]
    
    logging.debug(f"Detected background color: {most_common_color}")
    return most_common_color


def count_color_pixels(img_array, target_color, tolerance=30):
    """
    Count pixels matching target color within tolerance.
    Returns count and mask of matching pixels.
    """
    # Calculate color distance for each pixel
    diff = np.abs(img_array.astype(np.float32) - np.array(target_color))
    distance = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Create mask for pixels within tolerance
    matching_mask = distance <= tolerance
    matching_count = np.sum(matching_mask)
    
    return matching_count, matching_mask


def analyze_color_replacement(original_img, result_img):
    """
    Analyze the color replacement by comparing original and result images.
    Detects background color changes and measures transformation quality.
    """
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Detect original background color
    orig_bg_color = detect_background_color(orig_array)
    
    # Count original background pixels
    orig_bg_count, orig_bg_mask = count_color_pixels(orig_array, orig_bg_color, tolerance=25)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    orig_bg_percentage = (orig_bg_count / total_pixels) * 100
    
    # Count background pixels in result (should be reduced)
    result_bg_count, _ = count_color_pixels(result_array, orig_bg_color, tolerance=25)
    result_bg_percentage = (result_bg_count / total_pixels) * 100
    
    # Calculate background reduction
    bg_reduction = orig_bg_percentage - result_bg_percentage
    
    # Define target colors for fill (light blue, light gray)
    target_colors = {
        'light_blue': (173, 216, 230),
        'light_gray': (200, 200, 200),
        'blue': (135, 206, 235),      # Alternative blues
        'gray': (192, 192, 192)       # Alternative grays
    }
    
    # Check for new fill colors in result
    max_new_color_percentage = 0
    best_new_color = None
    
    for color_name, color_rgb in target_colors.items():
        new_color_count, _ = count_color_pixels(result_array, color_rgb, tolerance=30)
        new_color_percentage = (new_color_count / total_pixels) * 100
        
        # Compare with original to see increase
        orig_color_count, _ = count_color_pixels(orig_array, color_rgb, tolerance=30)
        orig_color_percentage = (orig_color_count / total_pixels) * 100
        
        color_increase = new_color_percentage - orig_color_percentage
        
        if color_increase > max_new_color_percentage:
            max_new_color_percentage = color_increase
            best_new_color = color_name
        
        logging.debug(f"{color_name}: orig={orig_color_percentage:.1f}%, result={new_color_percentage:.1f}%, increase={color_increase:.1f}%")
    
    # Analyze center region preservation (main subject should be unchanged)
    h, w = orig_array.shape[:2]
    center_y1, center_y2 = int(h * 0.25), int(h * 0.75)
    center_x1, center_x2 = int(w * 0.25), int(w * 0.75)
    
    orig_center = orig_array[center_y1:center_y2, center_x1:center_x2]
    result_center = result_array[center_y1:center_y2, center_x1:center_x2]
    
    # Calculate center region change
    center_diff = np.abs(orig_center.astype(np.float32) - result_center.astype(np.float32))
    center_change = np.mean(center_diff)
    center_change_percentage = (center_change / 255) * 100
    
    return {
        'orig_bg_percentage': orig_bg_percentage,
        'result_bg_percentage': result_bg_percentage,
        'bg_reduction': bg_reduction,
        'bg_reduction_ratio': bg_reduction / max(orig_bg_percentage, 0.1),
        'new_color_increase': max_new_color_percentage,
        'best_new_color': best_new_color,
        'center_change_percentage': center_change_percentage,
        'replacement_ratio': max_new_color_percentage / max(bg_reduction, 0.1)
    }


def check_fuzzy_select_fill(traj, env_info, task_info):
    """
    Main verifier function for fuzzy select and fill task.
    Checks:
    1. Background color was significantly reduced (fuzzy select worked)
    2. New fill color was significantly increased
    3. Main subject (center region) was preserved
    4. Replacement ratio is reasonable
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
        "/home/ga/Desktop/background_filled.jpg",
        "/home/ga/Desktop/background_filled.png", 
        "/home/ga/Desktop/background_filled.jpeg",
        "/home/ga/Desktop/product_filled.jpg",
        "/home/ga/Desktop/product_image_filled.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/product_image.jpg",
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
        
        # Analyze color replacement
        analysis = analyze_color_replacement(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original background: {analysis['orig_bg_percentage']:.1f}%")
        feedback_parts.append(f"Result background: {analysis['result_bg_percentage']:.1f}%")
        feedback_parts.append(f"Background reduced: {analysis['bg_reduction']:.1f}%")
        feedback_parts.append(f"New color increase: {analysis['new_color_increase']:.1f}%")
        if analysis['best_new_color']:
            feedback_parts.append(f"Fill color detected: {analysis['best_new_color']}")
        feedback_parts.append(f"Center region change: {analysis['center_change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Background color significantly reduced (at least 50% of original background)
        bg_reduced_significantly = analysis['bg_reduction'] >= max(2.0, analysis['orig_bg_percentage'] * 0.5)
        if bg_reduced_significantly:
            criteria_met += 1
        feedback_parts.append(f"Background reduced significantly: {'✅' if bg_reduced_significantly else '❌'}")
        
        # 2. New color introduced (at least 10% of total pixels)
        new_color_introduced = analysis['new_color_increase'] >= 10.0
        if new_color_introduced:
            criteria_met += 1
        feedback_parts.append(f"New fill color introduced: {'✅' if new_color_introduced else '❌'}")
        
        # 3. Center region preserved (less than 20% change on average)
        subject_preserved = analysis['center_change_percentage'] < 20.0
        if subject_preserved:
            criteria_met += 1
        feedback_parts.append(f"Main subject preserved: {'✅' if subject_preserved else '❌'}")
        
        # 4. Reasonable replacement ratio (new color increase should correlate with background reduction)
        reasonable_ratio = 0.3 <= analysis['replacement_ratio'] <= 2.0
        if reasonable_ratio:
            criteria_met += 1
        feedback_parts.append(f"Good replacement ratio: {'✅' if reasonable_ratio else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent fuzzy select and fill!")
        elif passed:
            feedback_parts.append("✅ Good fuzzy select and fill!")
        else:
            feedback_parts.append("❌ Fuzzy select and fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in fuzzy select fill verification: {e}")
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
    result = check_fuzzy_select_fill([], {}, {})
    print(f"Test result: {result}")