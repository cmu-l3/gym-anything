#!/usr/bin/env python3
"""
Verifier for GIMP auto normalize task.
Checks if image contrast and tonal distribution were improved through normalization.
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


def analyze_histogram(img):
    """
    Calculate comprehensive histogram statistics for tonal distribution analysis.
    """
    # Convert to grayscale for analysis
    if img.mode != 'L':
        gray = img.convert('L')
    else:
        gray = img
    
    img_array = np.array(gray)
    
    # Calculate histogram
    hist, bins = np.histogram(img_array, bins=256, range=(0, 255))
    
    # Find dynamic range (non-empty bins)
    non_zero_bins = np.where(hist > 0)[0]
    if len(non_zero_bins) > 0:
        black_point = non_zero_bins[0]
        white_point = non_zero_bins[-1]
        dynamic_range = white_point - black_point
    else:
        black_point, white_point, dynamic_range = 0, 0, 0
    
    # Calculate statistics
    mean_value = np.mean(img_array)
    std_dev = np.std(img_array)
    
    # Percentile analysis
    p1 = np.percentile(img_array, 1)
    p99 = np.percentile(img_array, 99)
    percentile_range = p99 - p1
    
    # Calculate range utilization (percentage of 0-255 range used)
    range_utilization = dynamic_range / 255.0
    
    # Check for clipping
    total_pixels = img_array.size
    black_clipped = np.sum(img_array <= 2)  # Very dark pixels
    white_clipped = np.sum(img_array >= 253)  # Very bright pixels
    black_clip_percent = (black_clipped / total_pixels) * 100
    white_clip_percent = (white_clipped / total_pixels) * 100
    
    return {
        'dynamic_range': dynamic_range,
        'range_utilization': range_utilization,
        'std_dev': std_dev,
        'mean_value': mean_value,
        'percentile_range': percentile_range,
        'black_point': black_point,
        'white_point': white_point,
        'p1': p1,
        'p99': p99,
        'black_clip_percent': black_clip_percent,
        'white_clip_percent': white_clip_percent
    }


def evaluate_normalization_quality(original_stats, result_stats):
    """
    Evaluate the quality of normalization based on histogram improvements.
    """
    feedback = []
    criteria_met = 0
    total_criteria = 4
    
    # Criterion 1: Dynamic range expanded (≥20% increase in range utilization)
    range_improvement = result_stats['range_utilization'] - original_stats['range_utilization']
    range_expanded = range_improvement >= 0.20
    if range_expanded:
        criteria_met += 1
    feedback.append(f"Range expansion: {'✅' if range_expanded else '❌'} ({range_improvement:.1%})")
    
    # Criterion 2: Contrast improved (≥15% increase in standard deviation)
    contrast_ratio = result_stats['std_dev'] / max(original_stats['std_dev'], 1.0)
    contrast_improved = contrast_ratio >= 1.15
    if contrast_improved:
        criteria_met += 1
    feedback.append(f"Contrast improved: {'✅' if contrast_improved else '❌'} ({contrast_ratio:.2f}x)")
    
    # Criterion 3: No excessive clipping (<2% of pixels clipped)
    total_clipping = result_stats['black_clip_percent'] + result_stats['white_clip_percent']
    no_clipping = total_clipping < 2.0
    if no_clipping:
        criteria_met += 1
    feedback.append(f"No excessive clipping: {'✅' if no_clipping else '❌'} ({total_clipping:.1f}%)")
    
    # Criterion 4: Meaningful modification (significant histogram differences)
    range_change = abs(range_improvement)
    contrast_change = abs(contrast_ratio - 1.0)
    meaningfully_changed = range_change >= 0.10 or contrast_change >= 0.10
    if meaningfully_changed:
        criteria_met += 1
    feedback.append(f"Image modified: {'✅' if meaningfully_changed else '❌'}")
    
    return criteria_met, total_criteria, feedback


def check_auto_normalize(traj, env_info, task_info):
    """
    Main verifier function for auto normalize task.
    Checks:
    1. Dynamic range was expanded (better use of 0-255 range)
    2. Contrast was improved (higher standard deviation)
    3. No excessive clipping occurred
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
        "/home/ga/Desktop/normalized_image.jpg",
        "/home/ga/Desktop/normalized_image.png",
        "/home/ga/Desktop/normalized_image.jpeg",
        "/home/ga/Desktop/low_contrast_image_normalized.jpg",
        "/home/ga/Desktop/enhanced_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/low_contrast_image.jpg",
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
        
        # Analyze histogram statistics
        original_stats = analyze_histogram(original_image)
        result_stats = analyze_histogram(result_image)
        
        # Evaluate normalization quality
        criteria_met, total_criteria, evaluation_feedback = evaluate_normalization_quality(
            original_stats, result_stats
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original range: {original_stats['black_point']}-{original_stats['white_point']} ({original_stats['range_utilization']:.1%})")
        feedback_parts.append(f"Result range: {result_stats['black_point']}-{result_stats['white_point']} ({result_stats['range_utilization']:.1%})")
        feedback_parts.append(f"Original contrast (std): {original_stats['std_dev']:.1f}")
        feedback_parts.append(f"Result contrast (std): {result_stats['std_dev']:.1f}")
        feedback_parts.extend(evaluation_feedback)
        
        # Calculate success based on criteria
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent normalization!")
        elif passed:
            feedback_parts.append("✅ Good normalization!")
        else:
            feedback_parts.append("❌ Normalization needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in auto normalize verification: {e}")
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
    result = check_auto_normalize([], {}, {})
    print(f"Test result: {result}")