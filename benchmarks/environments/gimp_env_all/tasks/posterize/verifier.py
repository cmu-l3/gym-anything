#!/usr/bin/env python3
"""
Verifier for GIMP posterize effect task.
Checks if posterize effect was applied with appropriate level reduction.
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


def analyze_unique_colors(img):
    """Count unique colors in the image."""
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    # Reshape to 2D array where each row is a pixel's RGB values
    pixels = img_array.reshape(-1, 3)
    
    # Find unique colors
    unique_colors = np.unique(pixels, axis=0)
    return len(unique_colors)


def analyze_histogram_peaks(img):
    """
    Analyze RGB histograms for characteristic posterize peaks.
    Returns info about peak distribution in each channel.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    peak_info = {}
    
    for channel, channel_name in enumerate(['Red', 'Green', 'Blue']):
        channel_data = img_array[:, :, channel].flatten()
        
        # Calculate histogram
        hist, bins = np.histogram(channel_data, bins=256, range=(0, 256))
        
        # Smooth histogram to reduce noise
        try:
            from scipy.ndimage import gaussian_filter1d
            smoothed_hist = gaussian_filter1d(hist.astype(float), sigma=2)
        except ImportError:
            # Fallback: simple moving average
            smoothed_hist = np.convolve(hist.astype(float), np.ones(5)/5, mode='same')
        
        # Find peaks (local maxima above threshold)
        threshold = np.max(smoothed_hist) * 0.15
        peaks = []
        
        for i in range(1, len(smoothed_hist) - 1):
            if (smoothed_hist[i] > threshold and 
                smoothed_hist[i] > smoothed_hist[i-1] and 
                smoothed_hist[i] > smoothed_hist[i+1]):
                peaks.append(i)
        
        peak_info[channel_name] = {
            'num_peaks': len(peaks),
            'peak_positions': peaks,
            'max_value': np.max(smoothed_hist)
        }
        
        logging.debug(f"{channel_name} channel: {len(peaks)} peaks at positions {peaks}")
    
    return peak_info


def analyze_color_clustering(img, expected_levels=4):
    """
    Analyze if colors cluster around expected posterize levels.
    For level 4: values should cluster near 0, 85, 170, 255
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Calculate expected level positions for posterize level 4
    level_step = 255 / (expected_levels - 1)
    expected_levels_values = [int(i * level_step) for i in range(expected_levels)]
    logging.debug(f"Expected posterize level values: {expected_levels_values}")
    
    clustering_scores = []
    
    for channel in range(3):
        channel_data = img_array[:, :, channel].flatten()
        
        # Find the most common values in this channel
        unique_vals, counts = np.unique(channel_data, return_counts=True)
        
        # Sort by frequency and get top values
        sorted_indices = np.argsort(counts)[::-1]
        top_values = unique_vals[sorted_indices[:expected_levels * 2]]  # Get more than expected in case of noise
        
        # Calculate how close top values are to expected levels
        min_distances = []
        for val in top_values[:expected_levels]:
            distances = [abs(val - expected) for expected in expected_levels_values]
            min_distances.append(min(distances))
        
        # Average minimum distance (lower is better)
        avg_min_distance = np.mean(min_distances) if min_distances else 255
        clustering_scores.append(avg_min_distance)
        
        logging.debug(f"Channel {channel}: top values {top_values[:4]}, avg min distance: {avg_min_distance}")
    
    # Good clustering means low average distance to expected levels
    overall_clustering_score = np.mean(clustering_scores)
    clustering_good = overall_clustering_score < 30  # Within 30 units on average
    
    return clustering_good, overall_clustering_score


def check_meaningful_change(original_img, result_img):
    """Check if the images show significant modification."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate mean difference across all channels
    if len(diff.shape) == 3:
        mean_diff = np.mean(diff)
        # Count significantly changed pixels (>20 intensity units change)
        significant_change = np.sqrt(np.sum(diff ** 2, axis=2)) > 20
    else:
        mean_diff = np.mean(diff)
        significant_change = diff > 20
    
    change_percentage = (np.sum(significant_change) / significant_change.size) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'significantly_changed': change_percentage > 15  # At least 15% of pixels changed significantly
    }


def check_posterize_effect(traj, env_info, task_info):
    """
    Main verifier function for posterize effect task.
    Checks:
    1. Significant reduction in unique colors
    2. Histogram shows banding (discrete peaks)
    3. Colors cluster around expected posterize levels
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
        "/home/ga/Desktop/posterized_image.png",
        "/home/ga/Desktop/posterized_image.jpg",
        "/home/ga/Desktop/posterized_image.jpeg",
        "/home/ga/Desktop/colorful_photo_posterized.jpg",
        "/home/ga/Desktop/posterize.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/colorful_photo.jpg",
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
        
        # 1. Analyze unique colors
        original_colors = analyze_unique_colors(original_image)
        result_colors = analyze_unique_colors(result_image)
        color_reduction_ratio = result_colors / max(original_colors, 1)
        
        # 2. Analyze histogram peaks
        peak_info = analyze_histogram_peaks(result_image)
        
        # Check if we have reasonable number of peaks per channel (2-8 for posterize level 4)
        peak_counts = [info['num_peaks'] for info in peak_info.values()]
        histogram_banding = all(2 <= count <= 8 for count in peak_counts)
        
        # 3. Analyze color clustering
        clustering_good, clustering_score = analyze_color_clustering(result_image, expected_levels=4)
        
        # 4. Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original colors: {original_colors}")
        feedback_parts.append(f"Result colors: {result_colors}")
        feedback_parts.append(f"Color reduction ratio: {color_reduction_ratio:.3f}")
        feedback_parts.append(f"Peak counts: R={peak_info['Red']['num_peaks']}, G={peak_info['Green']['num_peaks']}, B={peak_info['Blue']['num_peaks']}")
        feedback_parts.append(f"Clustering score: {clustering_score:.1f}")
        feedback_parts.append(f"Changed pixels: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant color reduction (to <500 colors or <5% of original)
        color_reduction_significant = result_colors < 500 or color_reduction_ratio < 0.05
        if color_reduction_significant:
            criteria_met += 1
        feedback_parts.append(f"Color reduction significant: {'✅' if color_reduction_significant else '❌'}")
        
        # 2. Histogram shows banding
        if histogram_banding:
            criteria_met += 1
        feedback_parts.append(f"Histogram banding detected: {'✅' if histogram_banding else '❌'}")
        
        # 3. Good color clustering
        if clustering_good:
            criteria_met += 1
        feedback_parts.append(f"Color clustering good: {'✅' if clustering_good else '❌'}")
        
        # 4. Significant change
        if change_analysis['significantly_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image significantly changed: {'✅' if change_analysis['significantly_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent posterize effect applied!")
        elif passed:
            feedback_parts.append("✅ Good posterize effect applied!")
        else:
            feedback_parts.append("❌ Posterize effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in posterize verification: {e}")
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
    result = check_posterize_effect([], {}, {})
    print(f"Test result: {result}")