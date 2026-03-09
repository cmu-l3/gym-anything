#!/usr/bin/env python3
"""
Verifier for GIMP vignette effect task.
Checks if a vignette effect was applied by analyzing edge vs center brightness.
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


def analyze_regional_brightness(img):
    """
    Analyze brightness in different regions of the image.
    Returns brightness statistics for edge and center regions.
    """
    # Convert to grayscale for luminosity analysis
    if img.mode != 'L':
        gray_img = img.convert('L')
    else:
        gray_img = img
    
    img_array = np.array(gray_img)
    height, width = img_array.shape
    
    # Define regions
    edge_width = int(width * 0.20)  # Outer 20% border
    edge_height = int(height * 0.20)
    
    center_x_start = int(width * 0.30)  # Center 40% region
    center_x_end = int(width * 0.70)
    center_y_start = int(height * 0.30)
    center_y_end = int(height * 0.70)
    
    # Extract edge regions (top, bottom, left, right borders)
    top_edge = img_array[:edge_height, :]
    bottom_edge = img_array[-edge_height:, :]
    left_edge = img_array[:, :edge_width]
    right_edge = img_array[:, -edge_width:]
    
    # Combine all edge pixels
    edge_pixels = np.concatenate([
        top_edge.flatten(),
        bottom_edge.flatten(),
        left_edge.flatten(),
        right_edge.flatten()
    ])
    
    # Extract center region
    center_pixels = img_array[center_y_start:center_y_end, 
                             center_x_start:center_x_end].flatten()
    
    # Calculate brightness statistics
    edge_brightness = np.mean(edge_pixels) if len(edge_pixels) > 0 else 0
    center_brightness = np.mean(center_pixels) if len(center_pixels) > 0 else 0
    
    # Calculate corner regions for additional analysis
    corner_size = min(edge_width, edge_height) // 2
    corners = [
        img_array[:corner_size, :corner_size],  # Top-left
        img_array[:corner_size, -corner_size:],  # Top-right
        img_array[-corner_size:, :corner_size],  # Bottom-left
        img_array[-corner_size:, -corner_size:]  # Bottom-right
    ]
    
    corner_pixels = np.concatenate([corner.flatten() for corner in corners])
    corner_brightness = np.mean(corner_pixels) if len(corner_pixels) > 0 else 0
    
    return {
        'edge_brightness': edge_brightness,
        'center_brightness': center_brightness,
        'corner_brightness': corner_brightness,
        'edge_to_center_ratio': edge_brightness / max(center_brightness, 1),
        'total_pixels': img_array.size
    }


def detect_vignette_effect(original_img, result_img):
    """
    Detect if a vignette effect was applied by comparing brightness patterns.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Analyze brightness in both images
    original_stats = analyze_regional_brightness(original_img)
    result_stats = analyze_regional_brightness(result_img)
    
    # Calculate changes
    edge_darkening_pct = ((original_stats['edge_brightness'] - result_stats['edge_brightness']) 
                         / original_stats['edge_brightness'] * 100)
    
    center_change_pct = abs((result_stats['center_brightness'] - original_stats['center_brightness'])
                           / original_stats['center_brightness'] * 100)
    
    corner_darkening_pct = ((original_stats['corner_brightness'] - result_stats['corner_brightness'])
                           / original_stats['corner_brightness'] * 100)
    
    # Check if edge-to-center ratio decreased (edges darker relative to center)
    original_ratio = original_stats['edge_to_center_ratio']
    result_ratio = result_stats['edge_to_center_ratio']
    ratio_decreased = result_ratio < original_ratio
    
    # Check for meaningful image modification
    orig_array = np.array(original_img.convert('L'))
    result_array = np.array(result_img.convert('L'))
    
    pixel_differences = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_difference = np.mean(pixel_differences)
    significantly_changed = mean_difference > 3.0  # At least 3 intensity units average change
    
    return {
        'edge_darkening_pct': edge_darkening_pct,
        'center_change_pct': center_change_pct,
        'corner_darkening_pct': corner_darkening_pct,
        'ratio_decreased': ratio_decreased,
        'significantly_changed': significantly_changed,
        'original_edge_brightness': original_stats['edge_brightness'],
        'result_edge_brightness': result_stats['edge_brightness'],
        'original_center_brightness': original_stats['center_brightness'],
        'result_center_brightness': result_stats['center_brightness'],
        'original_ratio': original_ratio,
        'result_ratio': result_ratio,
        'mean_pixel_difference': mean_difference
    }


def check_vignette_effect(traj, env_info, task_info):
    """
    Main verifier function for vignette effect task.
    Checks:
    1. Edges were significantly darkened (≥10% reduction)
    2. Center brightness was preserved (±5% change)
    3. Edge-to-center brightness ratio decreased
    4. Image was meaningfully modified
    5. Edge darkening is within reasonable range (10-40%)
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
        "/home/ga/Desktop/vignette_portrait.jpg",
        "/home/ga/Desktop/vignette_portrait.png",
        "/home/ga/Desktop/vignette_portrait.jpeg",
        "/home/ga/Desktop/portrait_vignette.jpg",
        "/home/ga/Desktop/portrait_image_vignette.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_image.jpg",
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
        
        # Analyze vignette effect
        vignette_analysis = detect_vignette_effect(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge darkening: {vignette_analysis['edge_darkening_pct']:.1f}%")
        feedback_parts.append(f"Center change: {vignette_analysis['center_change_pct']:.1f}%")
        feedback_parts.append(f"Corner darkening: {vignette_analysis['corner_darkening_pct']:.1f}%")
        feedback_parts.append(f"Ratio decreased: {'✅' if vignette_analysis['ratio_decreased'] else '❌'}")
        feedback_parts.append(f"Mean pixel diff: {vignette_analysis['mean_pixel_difference']:.1f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Edges darkened significantly (≥10%)
        edges_darkened = vignette_analysis['edge_darkening_pct'] >= 10.0
        if edges_darkened:
            criteria_met += 1
        feedback_parts.append(f"Edges darkened ≥10%: {'✅' if edges_darkened else '❌'}")
        
        # 2. Center brightness preserved (within 5% change)
        center_preserved = vignette_analysis['center_change_pct'] <= 5.0
        if center_preserved:
            criteria_met += 1
        feedback_parts.append(f"Center preserved: {'✅' if center_preserved else '❌'}")
        
        # 3. Edge-to-center ratio decreased (edges darker relative to center)
        if vignette_analysis['ratio_decreased']:
            criteria_met += 1
        feedback_parts.append(f"Contrast increased: {'✅' if vignette_analysis['ratio_decreased'] else '❌'}")
        
        # 4. Image was meaningfully modified
        if vignette_analysis['significantly_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if vignette_analysis['significantly_changed'] else '❌'}")
        
        # 5. Edge darkening within reasonable range (10-40%)
        reasonable_intensity = 10.0 <= vignette_analysis['edge_darkening_pct'] <= 40.0
        if reasonable_intensity:
            criteria_met += 1
        feedback_parts.append(f"Reasonable intensity: {'✅' if reasonable_intensity else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (75%)
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect vignette effect!")
        elif passed:
            feedback_parts.append("✅ Good vignette effect applied!")
        else:
            feedback_parts.append("❌ Vignette effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in vignette effect verification: {e}")
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
    result = check_vignette_effect([], {}, {})
    print(f"Test result: {result}")