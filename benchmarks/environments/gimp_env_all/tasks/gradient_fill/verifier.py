#!/usr/bin/env python3
"""
Verifier for GIMP gradient fill task.
Checks if a horizontal gradient was applied from left to right across the image.
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


def analyze_horizontal_gradient(image_array):
    """
    Analyze image for horizontal gradient characteristics.
    Returns metrics about gradient quality and direction.
    """
    if len(image_array.shape) != 3:
        return None
        
    height, width, channels = image_array.shape
    
    # Sample colors across horizontal strips at different vertical positions
    horizontal_samples = []
    sample_rows = max(5, height // 20)  # Sample at least 5 rows
    
    for i in range(sample_rows):
        y = int(i * height / sample_rows)
        if y >= height:
            y = height - 1
            
        row_colors = []
        sample_points = max(10, width // 10)  # Sample at least 10 points across width
        
        for j in range(sample_points):
            x = int(j * width / sample_points)
            if x >= width:
                x = width - 1
                
            # Convert RGB to grayscale for brightness analysis
            pixel_color = image_array[y, x]
            brightness = np.mean(pixel_color)  # Average RGB for brightness
            row_colors.append(brightness)
        
        horizontal_samples.append(row_colors)
    
    # Analyze gradient characteristics
    gradient_metrics = {
        'smoothness_scores': [],
        'monotonic_scores': [],
        'direction_consistency': [],
        'color_range': []
    }
    
    for row in horizontal_samples:
        if len(row) < 2:
            continue
            
        # Calculate differences between adjacent samples
        diffs = np.diff(row)
        
        # Check monotonicity (consistent direction)
        positive_changes = np.sum(diffs > 2)  # Threshold for significant change
        negative_changes = np.sum(diffs < -2)
        total_significant_changes = positive_changes + negative_changes
        
        if total_significant_changes > 0:
            monotonic_score = max(positive_changes, negative_changes) / total_significant_changes
        else:
            monotonic_score = 0.5  # No significant changes
        
        gradient_metrics['monotonic_scores'].append(monotonic_score)
        
        # Calculate smoothness (low variance in differences indicates smooth transition)
        if len(diffs) > 0:
            smoothness = 1.0 / (1.0 + np.var(diffs))
        else:
            smoothness = 0
        gradient_metrics['smoothness_scores'].append(smoothness)
        
        # Check color range (left vs right difference)
        left_avg = np.mean(row[:len(row)//3])   # Left third
        right_avg = np.mean(row[-len(row)//3:]) # Right third
        color_range = abs(right_avg - left_avg)
        gradient_metrics['color_range'].append(color_range)
        
        # Direction consistency (positive = left-to-right lightening, negative = darkening)
        direction = right_avg - left_avg
        gradient_metrics['direction_consistency'].append(direction)
    
    # Aggregate metrics
    return {
        'avg_smoothness': np.mean(gradient_metrics['smoothness_scores']) if gradient_metrics['smoothness_scores'] else 0,
        'avg_monotonic': np.mean(gradient_metrics['monotonic_scores']) if gradient_metrics['monotonic_scores'] else 0,
        'avg_color_range': np.mean(gradient_metrics['color_range']) if gradient_metrics['color_range'] else 0,
        'direction_consistency': np.mean(gradient_metrics['direction_consistency']) if gradient_metrics['direction_consistency'] else 0,
        'horizontal_variance': np.var(gradient_metrics['direction_consistency']) if len(gradient_metrics['direction_consistency']) > 1 else 0
    }


def detect_significant_change(original_img, result_img):
    """Check if the images are significantly different (gradient applied)."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)  # Pixels with >30 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'significantly_changed': change_percentage > 50  # At least 50% of pixels changed for gradient
    }


def check_gradient_fill(traj, env_info, task_info):
    """
    Main verifier function for gradient fill task.
    Checks:
    1. Horizontal gradient was applied from left to right
    2. Gradient transition is smooth
    3. Gradient covers the full image width
    4. Image was significantly modified from original
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
        "/home/ga/Desktop/gradient_filled.jpg",
        "/home/ga/Desktop/gradient_filled.png",
        "/home/ga/Desktop/gradient_filled.jpeg",
        "/home/ga/Desktop/landscape_gradient.jpg",
        "/home/ga/Desktop/landscape_image_gradient.jpg"
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
        
        # Convert result to RGB array for analysis
        result_array = np.array(result_image.convert('RGB'))
        
        # Analyze gradient characteristics
        gradient_analysis = analyze_horizontal_gradient(result_array)
        
        # Check for significant change from original
        change_analysis = detect_significant_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        
        if gradient_analysis:
            feedback_parts.append(f"Smoothness score: {gradient_analysis['avg_smoothness']:.2f}")
            feedback_parts.append(f"Monotonic score: {gradient_analysis['avg_monotonic']:.2f}")
            feedback_parts.append(f"Color range: {gradient_analysis['avg_color_range']:.1f}")
            feedback_parts.append(f"Direction consistency: {gradient_analysis['direction_consistency']:.1f}")
        
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Has horizontal gradient (good smoothness and monotonic scores)
        has_gradient = (gradient_analysis and 
                       gradient_analysis['avg_smoothness'] > 0.3 and 
                       gradient_analysis['avg_monotonic'] > 0.6)
        if has_gradient:
            criteria_met += 1
        feedback_parts.append(f"Horizontal gradient detected: {'✅' if has_gradient else '❌'}")
        
        # 2. Smooth transition (consistent direction and good smoothness)
        smooth_transition = (gradient_analysis and 
                           gradient_analysis['horizontal_variance'] < 5000 and 
                           gradient_analysis['avg_smoothness'] > 0.4)
        if smooth_transition:
            criteria_met += 1
        feedback_parts.append(f"Smooth transition: {'✅' if smooth_transition else '❌'}")
        
        # 3. Full coverage (significant color range across width)
        full_coverage = (gradient_analysis and 
                        gradient_analysis['avg_color_range'] > 30)
        if full_coverage:
            criteria_met += 1
        feedback_parts.append(f"Full width coverage: {'✅' if full_coverage else '❌'}")
        
        # 4. Significantly changed from original
        if change_analysis['significantly_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image significantly modified: {'✅' if change_analysis['significantly_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect horizontal gradient!")
        elif passed:
            feedback_parts.append("✅ Good gradient fill!")
        else:
            feedback_parts.append("❌ Gradient fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in gradient fill verification: {e}")
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
    result = check_gradient_fill([], {}, {})
    print(f"Test result: {result}")