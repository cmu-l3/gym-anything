#!/usr/bin/env python3
"""
Verifier for GIMP wind effect task.
Checks if wind effect was applied to create directional motion streaks.
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


def detect_wind_effect(original_img, result_img):
    """
    Advanced wind detection using directional gradient analysis.
    Returns analysis of wind effect characteristics.
    """
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for gradient analysis
    orig_gray = np.array(original_img.convert('L'))
    result_gray = np.array(result_img.convert('L'))
    
    try:
        # Calculate gradients in x and y directions using scipy
        from scipy.ndimage import sobel
        
        orig_gx = sobel(orig_gray, axis=1)
        orig_gy = sobel(orig_gray, axis=0)
        result_gx = sobel(result_gray, axis=1)
        result_gy = sobel(result_gray, axis=0)
        
        # Compare gradient magnitudes
        orig_gradient_mag = np.sqrt(orig_gx**2 + orig_gy**2)
        result_gradient_mag = np.sqrt(result_gx**2 + result_gy**2)
        
        # Detect directional asymmetry increase (key wind characteristic)
        orig_x_asymmetry = np.abs(np.mean(orig_gx))
        result_x_asymmetry = np.abs(np.mean(result_gx))
        orig_y_asymmetry = np.abs(np.mean(orig_gy))
        result_y_asymmetry = np.abs(np.mean(result_gy))
        
        # Wind effect should increase directional gradient asymmetry
        x_increase = result_x_asymmetry > orig_x_asymmetry * 1.5
        y_increase = result_y_asymmetry > orig_y_asymmetry * 1.5
        directional_effect = x_increase or y_increase
        
        # Calculate overall gradient change (wind adds streaks = more gradients)
        gradient_increase = np.mean(result_gradient_mag) > np.mean(orig_gradient_mag) * 1.1
        
        # Analyze directional streaking in difference image
        delta = np.abs(orig_gray.astype(np.float32) - result_gray.astype(np.float32))
        
        # Wind creates elongated changes, not uniform ones
        delta_gx = np.abs(sobel(delta, axis=1))
        delta_gy = np.abs(sobel(delta, axis=0))
        
        # Calculate directional ratio
        mean_delta_gx = np.mean(delta_gx)
        mean_delta_gy = np.mean(delta_gy)
        directional_ratio = max(mean_delta_gx / (mean_delta_gy + 1e-6),
                               mean_delta_gy / (mean_delta_gx + 1e-6))
        
        # Wind should create anisotropic (directional) changes
        anisotropic_change = directional_ratio > 1.3
        
        # Overall change magnitude
        mean_delta = np.mean(delta)
        significant_change = mean_delta > 5
        appropriate_strength = mean_delta < 50  # Not too extreme
        
        return {
            'wind_detected': directional_effect and gradient_increase,
            'directional_consistency': anisotropic_change,
            'appropriate_strength': significant_change and appropriate_strength,
            'edge_based': gradient_increase,
            'image_modified': significant_change,
            'directional_ratio': directional_ratio,
            'mean_delta': mean_delta,
            'x_asymmetry_increase': result_x_asymmetry / max(orig_x_asymmetry, 1e-6),
            'y_asymmetry_increase': result_y_asymmetry / max(orig_y_asymmetry, 1e-6)
        }
        
    except ImportError:
        # Fallback analysis without scipy
        logging.warning("Scipy not available, using basic wind detection")
        
        # Simple gradient approximation using numpy
        orig_gx = np.gradient(orig_gray, axis=1)
        orig_gy = np.gradient(orig_gray, axis=0)
        result_gx = np.gradient(result_gray, axis=1)
        result_gy = np.gradient(result_gray, axis=0)
        
        # Basic directional analysis
        orig_x_var = np.var(orig_gx)
        result_x_var = np.var(result_gx)
        orig_y_var = np.var(orig_gy)
        result_y_var = np.var(result_gy)
        
        directional_change = (result_x_var > orig_x_var * 1.2) or (result_y_var > orig_y_var * 1.2)
        
        # Calculate pixel difference
        delta = np.abs(orig_gray.astype(np.float32) - result_gray.astype(np.float32))
        mean_delta = np.mean(delta)
        significant_change = mean_delta > 5
        
        return {
            'wind_detected': directional_change,
            'directional_consistency': directional_change,
            'appropriate_strength': significant_change and mean_delta < 50,
            'edge_based': directional_change,
            'image_modified': significant_change,
            'directional_ratio': 1.0,
            'mean_delta': mean_delta
        }


def check_wind_effect(traj, env_info, task_info):
    """
    Main verifier function for wind effect task.
    Checks:
    1. Wind effect was applied (directional streaking detected)
    2. Effect shows directional consistency
    3. Effect strength is appropriate (visible but not overwhelming)
    4. Effect is edge-based (follows image features)
    5. Image was meaningfully modified
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
        "/home/ga/Desktop/wind_effect.png",
        "/home/ga/Desktop/wind_effect.jpg",
        "/home/ga/Desktop/wind_effect.jpeg",
        "/home/ga/Desktop/wind_subject_edited.jpg",
        "/home/ga/Desktop/wind_subject_effect.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/wind_subject.jpg",
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
        
        # Analyze wind effect
        wind_analysis = detect_wind_effect(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Mean pixel change: {wind_analysis['mean_delta']:.1f}")
        feedback_parts.append(f"Directional ratio: {wind_analysis['directional_ratio']:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Wind effect detected
        if wind_analysis['wind_detected']:
            criteria_met += 1
        feedback_parts.append(f"Wind effect detected: {'✅' if wind_analysis['wind_detected'] else '❌'}")
        
        # 2. Directional consistency
        if wind_analysis['directional_consistency']:
            criteria_met += 1
        feedback_parts.append(f"Directional consistency: {'✅' if wind_analysis['directional_consistency'] else '❌'}")
        
        # 3. Appropriate strength
        if wind_analysis['appropriate_strength']:
            criteria_met += 1
        feedback_parts.append(f"Appropriate strength: {'✅' if wind_analysis['appropriate_strength'] else '❌'}")
        
        # 4. Edge-based trails
        if wind_analysis['edge_based']:
            criteria_met += 1
        feedback_parts.append(f"Edge-based trails: {'✅' if wind_analysis['edge_based'] else '❌'}")
        
        # 5. Image modified
        if wind_analysis['image_modified']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if wind_analysis['image_modified'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent wind effect application!")
        elif passed:
            feedback_parts.append("✅ Good wind effect!")
        else:
            feedback_parts.append("❌ Wind effect needs improvement")
        
        # Add diagnostic information
        if 'x_asymmetry_increase' in wind_analysis:
            feedback_parts.append(f"X-direction change: {wind_analysis['x_asymmetry_increase']:.2f}x")
        if 'y_asymmetry_increase' in wind_analysis:
            feedback_parts.append(f"Y-direction change: {wind_analysis['y_asymmetry_increase']:.2f}x")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in wind effect verification: {e}")
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
    result = check_wind_effect([], {}, {})
    print(f"Test result: {result}")