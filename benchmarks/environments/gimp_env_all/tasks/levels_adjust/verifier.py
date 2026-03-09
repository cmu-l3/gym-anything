#!/usr/bin/env python3
"""
Verifier for GIMP levels adjustment task.
Checks if an underexposed image was properly corrected using levels adjustment.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def setup_verification_environment(original_container_path, possible_result_paths, copy_from_env, search_dir="/home/ga/Desktop"):
    """
    Set up verification environment with fallback file search.
    Returns success status and file info dict.
    """
    temp_dir = tempfile.mkdtemp()
    temp_path = Path(temp_dir)
    
    # Copy original file
    original_host_path = temp_path / "original.jpg"
    success, error = copy_file_from_container(copy_from_env, original_container_path, original_host_path)
    if not success:
        return False, {"error": f"Could not access original image: {error}"}
    
    # Try to find result file
    result_host_path = temp_path / "result.jpg"
    result_container_path = None
    
    for result_path in possible_result_paths:
        success, error = copy_file_from_container(copy_from_env, result_path, result_host_path)
        if success:
            result_container_path = result_path
            logging.debug(f"Found result image at: {result_path}")
            break
    
    if not result_container_path:
        return False, {"error": f"Could not find result image. Tried: {[Path(p).name for p in possible_result_paths]}"}
    
    return True, {
        "temp_dir": temp_dir,
        "original_path": original_host_path,
        "result_path": result_host_path,
        "result_container_path": result_container_path
    }


def cleanup_verification_environment(temp_dir):
    """Clean up temporary verification files."""
    import shutil
    if temp_dir and Path(temp_dir).exists():
        try:
            shutil.rmtree(temp_dir)
        except Exception as e:
            logging.warning(f"Could not clean up temp directory {temp_dir}: {e}")


def analyze_brightness_improvement(original_img, result_img):
    """
    Analyze brightness improvement between original and result images.
    Returns brightness metrics.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for brightness analysis
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
        
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    # Calculate mean brightness (0-255 scale)
    original_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    original_brightness = np.mean(original_array)
    result_brightness = np.mean(result_array)
    
    # Convert to percentage (0-100 scale)
    original_brightness_pct = (original_brightness / 255.0) * 100
    result_brightness_pct = (result_brightness / 255.0) * 100
    
    brightness_increase = result_brightness_pct - original_brightness_pct
    
    return {
        'original_brightness': original_brightness_pct,
        'result_brightness': result_brightness_pct,
        'brightness_increase': brightness_increase,
        'significantly_brighter': brightness_increase >= 15.0  # At least 15 percentage points
    }


def analyze_contrast_improvement(original_img, result_img):
    """
    Analyze contrast improvement using standard deviation of pixel values.
    Higher standard deviation indicates better contrast.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for contrast analysis
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
        
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    original_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    original_contrast = np.std(original_array)
    result_contrast = np.std(result_array)
    
    contrast_improvement = result_contrast - original_contrast
    
    return {
        'original_contrast': original_contrast,
        'result_contrast': result_contrast,
        'contrast_improvement': contrast_improvement,
        'contrast_enhanced': contrast_improvement > 0  # Any positive increase is good
    }


def analyze_histogram_distribution(original_img, result_img):
    """
    Analyze histogram distribution to see if tonal range utilization improved.
    """
    # Ensure images are same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale
    if original_img.mode != 'L':
        original_gray = original_img.convert('L')
    else:
        original_gray = original_img
        
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    original_array = np.array(original_gray)
    result_array = np.array(result_gray)
    
    # Calculate histograms
    original_hist, _ = np.histogram(original_array, bins=256, range=(0, 255))
    result_hist, _ = np.histogram(result_array, bins=256, range=(0, 255))
    
    # Calculate tonal range utilization (how many bins have significant values)
    min_pixels_per_bin = original_array.size * 0.001  # At least 0.1% of pixels
    original_used_bins = np.sum(original_hist > min_pixels_per_bin)
    result_used_bins = np.sum(result_hist > min_pixels_per_bin)
    
    # Calculate distribution spread
    original_spread = np.std(np.nonzero(original_hist)[0]) if np.any(original_hist) else 0
    result_spread = np.std(np.nonzero(result_hist)[0]) if np.any(result_hist) else 0
    
    distribution_improved = result_used_bins > original_used_bins or result_spread > original_spread
    
    return {
        'original_used_bins': original_used_bins,
        'result_used_bins': result_used_bins,
        'original_spread': original_spread,
        'result_spread': result_spread,
        'distribution_improved': distribution_improved
    }


def check_clipping_levels(result_img):
    """
    Check for excessive clipping in shadows and highlights.
    Returns clipping analysis.
    """
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    result_array = np.array(result_gray)
    total_pixels = result_array.size
    
    # Count pixels at extreme values
    black_clipped = np.sum(result_array <= 5)  # Near black
    white_clipped = np.sum(result_array >= 250)  # Near white
    
    black_clip_ratio = (black_clipped / total_pixels) * 100
    white_clip_ratio = (white_clipped / total_pixels) * 100
    
    # Acceptable clipping thresholds
    acceptable_clipping = black_clip_ratio < 5.0 and white_clip_ratio < 5.0
    
    return {
        'black_clip_ratio': black_clip_ratio,
        'white_clip_ratio': white_clip_ratio,
        'acceptable_clipping': acceptable_clipping
    }


def check_levels_adjustment(traj, env_info, task_info):
    """
    Main verifier function for levels adjustment task.
    Checks:
    1. Brightness increased significantly (≥15 percentage points)
    2. Contrast enhanced (standard deviation increased)
    3. Better histogram distribution
    4. No severe clipping occurred
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
        "/home/ga/Desktop/levels_corrected.jpg",
        "/home/ga/Desktop/levels_corrected.png",
        "/home/ga/Desktop/levels_corrected.jpeg",
        "/home/ga/Desktop/underexposed_landscape_corrected.jpg",
        "/home/ga/Desktop/corrected_landscape.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/underexposed_landscape.jpg",
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
        
        # Analyze brightness improvement
        brightness_analysis = analyze_brightness_improvement(original_image, result_image)
        
        # Analyze contrast improvement
        contrast_analysis = analyze_contrast_improvement(original_image, result_image)
        
        # Analyze histogram distribution
        histogram_analysis = analyze_histogram_distribution(original_image, result_image)
        
        # Check clipping levels
        clipping_analysis = check_clipping_levels(result_image)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size or not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original brightness: {brightness_analysis['original_brightness']:.1f}%")
        feedback_parts.append(f"Result brightness: {brightness_analysis['result_brightness']:.1f}%")
        feedback_parts.append(f"Brightness increase: {brightness_analysis['brightness_increase']:.1f}%")
        feedback_parts.append(f"Original contrast: {contrast_analysis['original_contrast']:.1f}")
        feedback_parts.append(f"Result contrast: {contrast_analysis['result_contrast']:.1f}")
        feedback_parts.append(f"Black clipping: {clipping_analysis['black_clip_ratio']:.1f}%")
        feedback_parts.append(f"White clipping: {clipping_analysis['white_clip_ratio']:.1f}%")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Brightness increased significantly (≥15 percentage points)
        if brightness_analysis['significantly_brighter']:
            criteria_met += 1
        feedback_parts.append(f"Brightness increased ≥15%: {'✅' if brightness_analysis['significantly_brighter'] else '❌'}")
        
        # 2. Contrast enhanced
        if contrast_analysis['contrast_enhanced']:
            criteria_met += 1
        feedback_parts.append(f"Contrast enhanced: {'✅' if contrast_analysis['contrast_enhanced'] else '❌'}")
        
        # 3. Better histogram distribution
        if histogram_analysis['distribution_improved']:
            criteria_met += 1
        feedback_parts.append(f"Distribution improved: {'✅' if histogram_analysis['distribution_improved'] else '❌'}")
        
        # 4. No severe clipping
        if clipping_analysis['acceptable_clipping']:
            criteria_met += 1
        feedback_parts.append(f"No severe clipping: {'✅' if clipping_analysis['acceptable_clipping'] else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent levels correction!")
        elif passed:
            feedback_parts.append("✅ Good levels correction!")
        else:
            feedback_parts.append("❌ Levels correction needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in levels adjustment verification: {e}")
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
    result = check_levels_adjustment([], {}, {})
    print(f"Test result: {result}")