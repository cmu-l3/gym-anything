#!/usr/bin/env python3
"""
Verifier for GIMP color enhancement task.
Checks if Color Enhance was applied to improve color distribution and vibrancy.
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

# Try to import OpenCV for advanced analysis
try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logging.warning("OpenCV not available, using PIL-based analysis")


def analyze_saturation_improvement(orig_img, result_img):
    """
    Compare saturation levels between original and enhanced images using HSV analysis.
    """
    if orig_img.size != result_img.size:
        result_img = result_img.resize(orig_img.size)
    
    if HAS_CV2:
        # Use OpenCV for more accurate HSV conversion
        orig_array = np.array(orig_img.convert('RGB'))
        result_array = np.array(result_img.convert('RGB'))
        
        orig_hsv = cv2.cvtColor(orig_array, cv2.COLOR_RGB2HSV)
        result_hsv = cv2.cvtColor(result_array, cv2.COLOR_RGB2HSV)
        
        orig_sat = np.mean(orig_hsv[:, :, 1])
        result_sat = np.mean(result_hsv[:, :, 1])
    else:
        # Fallback to PIL-based HSV analysis
        orig_hsv = orig_img.convert('HSV')
        result_hsv = result_img.convert('HSV')
        
        orig_sat = np.mean(np.array(orig_hsv)[:, :, 1])
        result_sat = np.mean(np.array(result_hsv)[:, :, 1])
    
    if orig_sat > 0:
        sat_increase_pct = ((result_sat - orig_sat) / orig_sat) * 100
    else:
        sat_increase_pct = 0
    
    return {
        'original_saturation': orig_sat,
        'result_saturation': result_sat,
        'saturation_increase_pct': sat_increase_pct,
        'improved': sat_increase_pct >= 5.0  # At least 5% improvement
    }


def analyze_histogram_distribution(orig_img, result_img):
    """
    Measure improvement in color value distribution using histogram analysis.
    """
    if orig_img.size != result_img.size:
        result_img = result_img.resize(orig_img.size)
    
    orig_array = np.array(orig_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate standard deviation across all color channels
    orig_std = np.std(orig_array)
    result_std = np.std(result_array)
    
    # Calculate histogram spread for each channel
    orig_histograms = []
    result_histograms = []
    
    for channel in range(3):  # R, G, B channels
        orig_hist = np.histogram(orig_array[:, :, channel], bins=256, range=(0, 256))[0]
        result_hist = np.histogram(result_array[:, :, channel], bins=256, range=(0, 256))[0]
        orig_histograms.append(orig_hist)
        result_histograms.append(result_hist)
    
    # Calculate effective range (5th to 95th percentile)
    orig_range = np.percentile(orig_array, 95) - np.percentile(orig_array, 5)
    result_range = np.percentile(result_array, 95) - np.percentile(result_array, 5)
    
    distribution_improvement = result_std > orig_std * 1.05  # 5% increase in std dev
    
    return {
        'original_std': orig_std,
        'result_std': result_std,
        'original_range': orig_range,
        'result_range': result_range,
        'improved_distribution': distribution_improvement
    }


def analyze_color_richness(orig_img, result_img):
    """
    Measure increase in color variety and vibrancy.
    """
    if orig_img.size != result_img.size:
        result_img = result_img.resize(orig_img.size)
    
    orig_array = np.array(orig_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Count unique colors (binned to reduce noise)
    bin_factor = 8  # Reduce to 32 levels per channel
    orig_binned = orig_array // bin_factor
    result_binned = result_array // bin_factor
    
    # Convert to single values for unique counting
    orig_combined = orig_binned[:, :, 0] * 32*32 + orig_binned[:, :, 1] * 32 + orig_binned[:, :, 2]
    result_combined = result_binned[:, :, 0] * 32*32 + result_binned[:, :, 1] * 32 + result_binned[:, :, 2]
    
    orig_unique = len(np.unique(orig_combined))
    result_unique = len(np.unique(result_combined))
    
    # Calculate pixel-to-pixel variance
    orig_variance = np.var(orig_array)
    result_variance = np.var(result_array)
    
    richness_improved = result_unique >= orig_unique * 1.1  # 10% more distinct colors
    
    return {
        'original_unique_colors': orig_unique,
        'result_unique_colors': result_unique,
        'original_variance': orig_variance,
        'result_variance': result_variance,
        'richness_improved': richness_improved
    }


def check_quality_preservation(orig_img, result_img):
    """
    Ensure enhancement didn't cause excessive clipping or quality loss.
    """
    if orig_img.size != result_img.size:
        result_img = result_img.resize(orig_img.size)
    
    result_array = np.array(result_img.convert('RGB'))
    
    # Check for clipping (pixels at extreme values)
    clipped_white = np.sum(result_array >= 250)  # Very bright pixels
    clipped_black = np.sum(result_array <= 5)    # Very dark pixels
    total_pixels = result_array.size
    
    clipping_percentage = (clipped_white + clipped_black) / total_pixels * 100
    
    # Check if enhancement maintained detail
    orig_array = np.array(orig_img.convert('RGB'))
    
    # Compare local contrast (standard deviation in small regions)
    from scipy.ndimage import uniform_filter
    window_size = 9
    
    try:
        orig_local_std = uniform_filter(np.std(orig_array, axis=2), size=window_size)
        result_local_std = uniform_filter(np.std(result_array, axis=2), size=window_size)
        
        detail_preserved = np.mean(result_local_std) >= np.mean(orig_local_std) * 0.8
    except:
        # Fallback if scipy not available
        detail_preserved = True
    
    return {
        'clipping_percentage': clipping_percentage,
        'quality_preserved': clipping_percentage < 5.0,  # Less than 5% clipping
        'detail_preserved': detail_preserved
    }


def check_color_enhance(traj, env_info, task_info):
    """
    Main verifier function for color enhancement task.
    Checks:
    1. Saturation increased by at least 5%
    2. Color histogram shows better distribution
    3. Color richness and variety improved
    4. Quality preserved without excessive clipping
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
        "/home/ga/Desktop/enhanced_colors.jpg",
        "/home/ga/Desktop/enhanced_colors.png",
        "/home/ga/Desktop/enhanced_colors.jpeg",
        "/home/ga/Desktop/enhanced.jpg",
        "/home/ga/Desktop/color_enhanced.jpg",
        "/home/ga/Desktop/flat_photo_enhanced.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flat_photo.jpg",
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
        
        # Analyze color enhancement
        saturation_analysis = analyze_saturation_improvement(original_image, result_image)
        distribution_analysis = analyze_histogram_distribution(original_image, result_image)
        richness_analysis = analyze_color_richness(original_image, result_image)
        quality_analysis = check_quality_preservation(original_image, result_image)
        
        # Check if image was modified
        images_different = not np.array_equal(
            np.array(original_image.convert('RGB')), 
            np.array(result_image.convert('RGB'))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Saturation increase: {saturation_analysis['saturation_increase_pct']:.1f}%")
        feedback_parts.append(f"Original std: {distribution_analysis['original_std']:.1f}")
        feedback_parts.append(f"Result std: {distribution_analysis['result_std']:.1f}")
        feedback_parts.append(f"Color richness: {richness_analysis['result_unique_colors']} colors")
        feedback_parts.append(f"Clipping: {quality_analysis['clipping_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Saturation increased by at least 5%
        if saturation_analysis['improved']:
            criteria_met += 1
        feedback_parts.append(f"Saturation improved: {'✅' if saturation_analysis['improved'] else '❌'}")
        
        # 2. Better color distribution
        if distribution_analysis['improved_distribution']:
            criteria_met += 1
        feedback_parts.append(f"Distribution improved: {'✅' if distribution_analysis['improved_distribution'] else '❌'}")
        
        # 3. Enhanced color richness
        if richness_analysis['richness_improved']:
            criteria_met += 1
        feedback_parts.append(f"Richness enhanced: {'✅' if richness_analysis['richness_improved'] else '❌'}")
        
        # 4. Quality maintained
        if quality_analysis['quality_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Quality preserved: {'✅' if quality_analysis['quality_preserved'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent color enhancement!")
        elif passed:
            feedback_parts.append("✅ Good color enhancement!")
        else:
            feedback_parts.append("❌ Color enhancement needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in color enhancement verification: {e}")
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
    result = check_color_enhance([], {}, {})
    print(f"Test result: {result}")