#!/usr/bin/env python3
"""
Verifier for GIMP ripple effect task.
Checks if ripple distortion was successfully applied to create wave patterns.
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


def detect_edges_simple(img_array):
    """Simple edge detection using gradient."""
    # Convert to grayscale if needed
    if len(img_array.shape) == 3:
        gray = np.mean(img_array, axis=2)
    else:
        gray = img_array
    
    # Simple gradient-based edge detection
    dx = np.abs(np.diff(gray, axis=1))
    dy = np.abs(np.diff(gray, axis=0))
    
    # Pad to match original size
    dx = np.pad(dx, ((0, 0), (0, 1)), mode='constant')
    dy = np.pad(dy, ((0, 1), (0, 0)), mode='constant')
    
    return dx + dy


def analyze_wave_patterns_in_profiles(original_img, result_img, num_samples=5):
    """
    Analyze intensity profiles along rows and columns to detect wave patterns.
    """
    if original_img.mode != 'L':
        orig_gray = np.array(original_img.convert('L'))
    else:
        orig_gray = np.array(original_img)
    
    if result_img.mode != 'L':
        result_gray = np.array(result_img.convert('L'))
    else:
        result_gray = np.array(result_img)
    
    height, width = orig_gray.shape
    
    wave_evidence = {
        'profiles_analyzed': 0,
        'profiles_with_waves': 0,
        'max_profile_variance_increase': 0,
        'avg_profile_change': 0
    }
    
    total_profile_change = 0
    
    # Sample rows at regular intervals
    row_indices = [int(i * height / (num_samples + 1)) for i in range(1, num_samples + 1)]
    
    for row_idx in row_indices:
        if row_idx >= height:
            continue
            
        orig_profile = orig_gray[row_idx, :]
        result_profile = result_gray[row_idx, :]
        
        # Calculate profile differences
        profile_diff = np.abs(result_profile.astype(float) - orig_profile.astype(float))
        avg_diff = np.mean(profile_diff)
        total_profile_change += avg_diff
        
        # Analyze variance (wave patterns create more variation)
        orig_variance = np.var(orig_profile)
        result_variance = np.var(result_profile)
        variance_increase = result_variance - orig_variance
        
        wave_evidence['max_profile_variance_increase'] = max(
            wave_evidence['max_profile_variance_increase'], variance_increase
        )
        
        wave_evidence['profiles_analyzed'] += 1
        
        # Check for wave-like patterns (increased local variation)
        if avg_diff > 3 and variance_increase > 10:  # Thresholds for wave detection
            wave_evidence['profiles_with_waves'] += 1
            logging.debug(f"Wave pattern detected in row {row_idx}: avg_diff={avg_diff:.2f}, var_increase={variance_increase:.2f}")
    
    if wave_evidence['profiles_analyzed'] > 0:
        wave_evidence['avg_profile_change'] = total_profile_change / wave_evidence['profiles_analyzed']
    
    return wave_evidence


def measure_distortion_magnitude(original_img, result_img):
    """
    Measure overall magnitude of geometric distortion.
    """
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(float) - result_array.astype(float))
    
    # Calculate magnitude of change per pixel
    magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Statistics
    mean_change = np.mean(magnitude)
    std_change = np.std(magnitude)
    
    # Percentage of significantly changed pixels
    significant_threshold = 15  # intensity units
    changed_pixels = np.sum(magnitude > significant_threshold)
    total_pixels = magnitude.shape[0] * magnitude.shape[1]
    change_percentage = (changed_pixels / total_pixels) * 100
    
    return {
        'mean_change': mean_change,
        'std_change': std_change,
        'change_percentage': change_percentage,
        'max_change': np.max(magnitude)
    }


def detect_ripple_via_edge_displacement(original_img, result_img):
    """
    Detect ripple distortion by analyzing edge displacement patterns.
    """
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Detect edges in both images
    orig_edges = detect_edges_simple(orig_array)
    result_edges = detect_edges_simple(result_array)
    
    # Find areas with strong edges in the original
    strong_edge_threshold = np.percentile(orig_edges, 85)  # Top 15% of edges
    strong_edge_mask = orig_edges > strong_edge_threshold
    
    if np.sum(strong_edge_mask) == 0:
        return {'edge_displacement_detected': False, 'avg_edge_displacement': 0}
    
    # Calculate differences in edge-rich areas
    edge_diff = np.abs(result_edges - orig_edges)
    edge_displacement = np.mean(edge_diff[strong_edge_mask])
    
    # Ripple creates moderate edge displacement
    displacement_detected = edge_displacement > 5  # Threshold for meaningful displacement
    
    return {
        'edge_displacement_detected': displacement_detected,
        'avg_edge_displacement': edge_displacement,
        'strong_edges_count': np.sum(strong_edge_mask)
    }


def check_ripple_effect(traj, env_info, task_info):
    """
    Main verifier function for ripple effect task.
    Checks:
    1. Significant geometric distortion occurred
    2. Wave-like patterns detected in image profiles
    3. Edge displacement consistent with ripple effect
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
        "/home/ga/Desktop/rippled_image.jpg",
        "/home/ga/Desktop/rippled_image.png", 
        "/home/ga/Desktop/rippled_image.jpeg",
        "/home/ga/Desktop/geometric_image_ripple.jpg",
        "/home/ga/Desktop/wave_effect.jpg",
        "/home/ga/Desktop/geometric_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/geometric_image.jpg",
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
        
        # Analyze distortion magnitude
        distortion_analysis = measure_distortion_magnitude(original_image, result_image)
        
        # Analyze wave patterns in profiles
        wave_analysis = analyze_wave_patterns_in_profiles(original_image, result_image)
        
        # Detect edge displacement
        edge_analysis = detect_ripple_via_edge_displacement(original_image, result_image)
        
        # Check if image was modified
        images_different = original_image.size == result_image.size and distortion_analysis['change_percentage'] > 1
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Mean pixel change: {distortion_analysis['mean_change']:.1f}")
        feedback_parts.append(f"Changed pixels: {distortion_analysis['change_percentage']:.1f}%")
        feedback_parts.append(f"Profiles with waves: {wave_analysis['profiles_with_waves']}/{wave_analysis['profiles_analyzed']}")
        feedback_parts.append(f"Avg profile change: {wave_analysis['avg_profile_change']:.1f}")
        feedback_parts.append(f"Edge displacement: {edge_analysis['avg_edge_displacement']:.1f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant distortion detected (at least 5% of pixels changed meaningfully)
        distortion_significant = distortion_analysis['change_percentage'] >= 5
        if distortion_significant:
            criteria_met += 1
        feedback_parts.append(f"Significant distortion: {'✅' if distortion_significant else '❌'}")
        
        # 2. Wave patterns detected in multiple profiles
        wave_patterns_detected = wave_analysis['profiles_with_waves'] >= 2
        if wave_patterns_detected:
            criteria_met += 1
        feedback_parts.append(f"Wave patterns detected: {'✅' if wave_patterns_detected else '❌'}")
        
        # 3. Appropriate magnitude (visible but not extreme)
        appropriate_magnitude = 3 <= distortion_analysis['mean_change'] <= 50
        if appropriate_magnitude:
            criteria_met += 1
        feedback_parts.append(f"Appropriate magnitude: {'✅' if appropriate_magnitude else '❌'}")
        
        # 4. Pattern consistency (edge displacement detected)
        pattern_consistent = edge_analysis['edge_displacement_detected']
        if pattern_consistent:
            criteria_met += 1
        feedback_parts.append(f"Pattern consistency: {'✅' if pattern_consistent else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent ripple effect!")
        elif passed:
            feedback_parts.append("✅ Good ripple effect detected!")
        else:
            feedback_parts.append("❌ Ripple effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in ripple effect verification: {e}")
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
    result = check_ripple_effect([], {}, {})
    print(f"Test result: {result}")