#!/usr/bin/env python3
"""
Verifier for GIMP threshold conversion task.
Checks if image was successfully converted to pure black-and-white (binary).
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


def analyze_binary_conversion(img):
    """
    Analyze image to determine if it's been successfully converted to binary (black/white).
    Returns detailed metrics about the conversion quality.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Calculate intensity (average of RGB for each pixel)
    intensity = np.mean(img_array, axis=2)
    
    total_pixels = intensity.size
    
    # Count pixels in different intensity ranges
    black_pixels = np.sum(intensity <= 30)           # Pure black
    dark_pixels = np.sum(intensity <= 50)            # Near black  
    mid_pixels = np.sum((intensity > 50) & (intensity < 200))  # Grayscale
    light_pixels = np.sum(intensity >= 200)          # Near white
    white_pixels = np.sum(intensity >= 225)          # Pure white
    
    # Calculate percentages
    black_percentage = (black_pixels / total_pixels) * 100
    dark_percentage = (dark_pixels / total_pixels) * 100
    mid_percentage = (mid_pixels / total_pixels) * 100
    light_percentage = (light_pixels / total_pixels) * 100
    white_percentage = (white_pixels / total_pixels) * 100
    
    # Calculate binary purity (strict black or white)
    binary_purity = (black_pixels + white_pixels) / total_pixels
    
    # Calculate extended binary (near-black or near-white)
    extended_binary = (dark_pixels + light_pixels) / total_pixels
    
    # Check for trivial results (all black or all white)
    is_trivial = (dark_percentage > 95) or (light_percentage > 95)
    
    return {
        'total_pixels': total_pixels,
        'black_pixels': black_pixels,
        'dark_pixels': dark_pixels,
        'mid_pixels': mid_pixels,
        'light_pixels': light_pixels,
        'white_pixels': white_pixels,
        'black_percentage': black_percentage,
        'dark_percentage': dark_percentage,
        'mid_percentage': mid_percentage,
        'light_percentage': light_percentage,
        'white_percentage': white_percentage,
        'binary_purity': binary_purity,
        'extended_binary': extended_binary,
        'is_trivial': is_trivial,
        'grayscale_eliminated': mid_percentage < 10,
        'good_binary_conversion': binary_purity >= 0.90 and not is_trivial
    }


def check_image_modification(original_img, result_img):
    """Check if the image was meaningfully modified from the original."""
    # Resize result to match original if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert both to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    if len(orig_array.shape) == 3:  # Color image
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        magnitude = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate percentage of significantly changed pixels
    significant_changes = np.sum(magnitude > 30)  # Pixels with >30 intensity change
    total_pixels = magnitude.size
    change_percentage = (significant_changes / total_pixels) * 100
    
    return {
        'change_percentage': change_percentage,
        'significantly_modified': change_percentage > 20  # At least 20% of pixels changed
    }


def assess_content_preservation(original_img, result_img):
    """
    Assess whether the binary conversion preserved recognizable content.
    Uses edge detection and structure preservation metrics.
    """
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
    
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Resize if needed
    if orig_gray.size != result_gray.size:
        result_gray = result_gray.resize(orig_gray.size)
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    # Simple edge detection using gradients
    orig_grad_x = np.abs(np.diff(orig_array, axis=1))
    orig_grad_y = np.abs(np.diff(orig_array, axis=0))
    orig_edges = np.sum(orig_grad_x) + np.sum(orig_grad_y)
    
    result_grad_x = np.abs(np.diff(result_array, axis=1))
    result_grad_y = np.abs(np.diff(result_array, axis=0))
    result_edges = np.sum(result_grad_x) + np.sum(result_grad_y)
    
    # Calculate edge preservation ratio
    edge_preservation = result_edges / max(orig_edges, 1)  # Avoid division by zero
    
    # Structure should be preserved (ratio between 0.3 and 3.0 indicates good preservation)
    content_preserved = 0.3 <= edge_preservation <= 3.0
    
    return {
        'orig_edges': orig_edges,
        'result_edges': result_edges,
        'edge_preservation_ratio': edge_preservation,
        'content_preserved': content_preserved
    }


def check_threshold_conversion(traj, env_info, task_info):
    """
    Main verifier function for threshold conversion task.
    Checks:
    1. Image was converted to binary (black and white only)
    2. Grayscale values were eliminated
    3. Content structure was preserved
    4. Result is not trivial (all black or all white)
    5. Image was meaningfully modified from original
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
        "/home/ga/Desktop/threshold_result.png",
        "/home/ga/Desktop/threshold_result.jpg", 
        "/home/ga/Desktop/threshold_result.jpeg",
        "/home/ga/Desktop/grayscale_image_threshold.png",
        "/home/ga/Desktop/binary_result.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/grayscale_image.jpg",
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
        
        # Analyze binary conversion
        binary_analysis = analyze_binary_conversion(result_image)
        
        # Check for meaningful modification
        change_analysis = check_image_modification(original_image, result_image)
        
        # Assess content preservation
        content_analysis = assess_content_preservation(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Binary purity: {binary_analysis['binary_purity']:.1%}")
        feedback_parts.append(f"Black pixels: {binary_analysis['black_percentage']:.1f}%")
        feedback_parts.append(f"White pixels: {binary_analysis['white_percentage']:.1f}%")
        feedback_parts.append(f"Grayscale remaining: {binary_analysis['mid_percentage']:.1f}%")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        feedback_parts.append(f"Edge preservation: {content_analysis['edge_preservation_ratio']:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. High binary purity (≥90% black or white pixels)
        if binary_analysis['binary_purity'] >= 0.90:
            criteria_met += 1
        feedback_parts.append(f"Binary purity ≥90%: {'✅' if binary_analysis['binary_purity'] >= 0.90 else '❌'}")
        
        # 2. Grayscale eliminated (<10% mid-tone pixels)
        if binary_analysis['grayscale_eliminated']:
            criteria_met += 1
        feedback_parts.append(f"Grayscale eliminated: {'✅' if binary_analysis['grayscale_eliminated'] else '❌'}")
        
        # 3. Content preserved (structure maintained)
        if content_analysis['content_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Content preserved: {'✅' if content_analysis['content_preserved'] else '❌'}")
        
        # 4. Not trivial (not all black or all white)
        if not binary_analysis['is_trivial']:
            criteria_met += 1
        feedback_parts.append(f"Balanced distribution: {'✅' if not binary_analysis['is_trivial'] else '❌'}")
        
        # 5. Significantly modified from original
        if change_analysis['significantly_modified']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['significantly_modified'] else '❌'}")
        
        # Calculate score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%) but we set threshold to 75% to account for minor variations
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect threshold conversion!")
        elif passed:
            feedback_parts.append("✅ Good threshold conversion!")
        else:
            feedback_parts.append("❌ Threshold conversion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in threshold conversion verification: {e}")
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
    result = check_threshold_conversion([], {}, {})
    print(f"Test result: {result}")