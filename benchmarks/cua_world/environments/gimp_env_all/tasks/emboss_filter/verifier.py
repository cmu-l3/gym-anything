#!/usr/bin/env python3
"""
Verifier for GIMP emboss filter task.
Checks if emboss filter was successfully applied to create 3D relief effect.
"""

import logging
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np
import sys
import os

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)


def calculate_edge_enhancement(original_img, result_img):
    """Calculate increase in edge prominence after emboss."""
    # Apply edge detection to both images
    orig_edges = original_img.filter(ImageFilter.FIND_EDGES)
    result_edges = result_img.filter(ImageFilter.FIND_EDGES)
    
    # Convert to arrays and calculate mean edge intensity
    orig_edge_array = np.array(orig_edges.convert('L'))
    result_edge_array = np.array(result_edges.convert('L'))
    
    orig_edge_mean = np.mean(orig_edge_array)
    result_edge_mean = np.mean(result_edge_array)
    
    edge_enhancement = result_edge_mean - orig_edge_mean
    
    return edge_enhancement, orig_edge_mean, result_edge_mean


def calculate_texture_enhancement(original_img, result_img):
    """Calculate increase in texture/detail after emboss."""
    # Convert to grayscale for texture analysis
    orig_gray = np.array(original_img.convert('L'))
    result_gray = np.array(result_img.convert('L'))
    
    # Calculate local standard deviation (texture measure)
    orig_std = np.std(orig_gray)
    result_std = np.std(result_gray)
    
    # Emboss typically increases local variation
    texture_increase = (result_std - orig_std) / max(orig_std, 1.0)
    
    return texture_increase, orig_std, result_std


def calculate_saturation_reduction(original_img, result_img):
    """Calculate reduction in color saturation typical of emboss."""
    # Convert to HSV to analyze saturation
    orig_hsv = np.array(original_img.convert('HSV'))
    result_hsv = np.array(result_img.convert('HSV'))
    
    # Extract saturation channel (index 1)
    orig_saturation = orig_hsv[:, :, 1]
    result_saturation = result_hsv[:, :, 1]
    
    orig_sat_mean = np.mean(orig_saturation)
    result_sat_mean = np.mean(result_saturation)
    
    # Calculate saturation reduction (emboss typically desaturates)
    saturation_reduction = (orig_sat_mean - result_sat_mean) / max(orig_sat_mean, 1.0)
    
    return saturation_reduction, orig_sat_mean, result_sat_mean


def calculate_overall_change(original_img, result_img):
    """Calculate overall pixel-wise change magnitude."""
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB arrays
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array - result_array)
    
    # Calculate mean absolute difference
    mean_change = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels (>30 intensity change)
    significant_changes = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_changes / total_pixels) * 100
    
    return mean_change, change_percentage


def detect_emboss_effect(original_img, result_img):
    """
    Comprehensive emboss effect detection using multiple statistical measures.
    """
    # 1. Edge enhancement analysis
    edge_enhancement, orig_edge_mean, result_edge_mean = calculate_edge_enhancement(original_img, result_img)
    
    # 2. Texture enhancement analysis  
    texture_increase, orig_std, result_std = calculate_texture_enhancement(original_img, result_img)
    
    # 3. Color saturation reduction analysis
    saturation_reduction, orig_sat_mean, result_sat_mean = calculate_saturation_reduction(original_img, result_img)
    
    # 4. Overall change magnitude
    mean_change, change_percentage = calculate_overall_change(original_img, result_img)
    
    # Determine if criteria are met
    criteria = {
        'edge_enhancement': edge_enhancement > 10,  # Edges more prominent
        'texture_increase': texture_increase > 0.1,  # 10% increase in variation
        'saturation_reduction': saturation_reduction > 0.15,  # 15% less saturated
        'sufficient_change': mean_change > 20  # Significant overall change
    }
    
    return {
        'criteria': criteria,
        'metrics': {
            'edge_enhancement': edge_enhancement,
            'orig_edge_mean': orig_edge_mean,
            'result_edge_mean': result_edge_mean,
            'texture_increase': texture_increase,
            'orig_std': orig_std,
            'result_std': result_std,
            'saturation_reduction': saturation_reduction,
            'orig_saturation': orig_sat_mean,
            'result_saturation': result_sat_mean,
            'mean_change': mean_change,
            'change_percentage': change_percentage
        }
    }


def check_emboss_filter(traj, env_info, task_info):
    """
    Main verifier function for emboss filter task.
    Checks:
    1. Edge enhancement (emboss emphasizes edges)
    2. Texture increase (local variation increases)
    3. Saturation reduction (emboss typically desaturates)
    4. Sufficient overall change (image was meaningfully transformed)
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
        "/home/ga/Desktop/embossed_image.jpg",
        "/home/ga/Desktop/embossed_image.png",
        "/home/ga/Desktop/embossed_image.jpeg",
        "/home/ga/Desktop/portrait_detail_embossed.jpg",
        "/home/ga/Desktop/portrait_embossed.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_detail.jpg",
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
        
        # Detect emboss effect using statistical analysis
        emboss_analysis = detect_emboss_effect(original_image, result_image)
        
        criteria = emboss_analysis['criteria']
        metrics = emboss_analysis['metrics']
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge enhancement: {metrics['edge_enhancement']:.1f} ({'✅' if criteria['edge_enhancement'] else '❌'})")
        feedback_parts.append(f"Texture increase: {metrics['texture_increase']:.2f} ({'✅' if criteria['texture_increase'] else '❌'})")
        feedback_parts.append(f"Saturation reduction: {metrics['saturation_reduction']:.2f} ({'✅' if criteria['saturation_reduction'] else '❌'})")
        feedback_parts.append(f"Mean pixel change: {metrics['mean_change']:.1f} ({'✅' if criteria['sufficient_change'] else '❌'})")
        feedback_parts.append(f"Pixels changed: {metrics['change_percentage']:.1f}%")
        
        # Calculate success based on criteria met
        criteria_met = sum(criteria.values())
        total_criteria = len(criteria)
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect emboss effect applied!")
        elif passed:
            feedback_parts.append("✅ Good emboss effect applied!")
        else:
            feedback_parts.append("❌ Emboss effect not detected or insufficient")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in emboss filter verification: {e}")
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
    result = check_emboss_filter([], {}, {})
    print(f"Test result: {result}")