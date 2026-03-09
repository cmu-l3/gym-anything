#!/usr/bin/env python3
"""
Verifier for GIMP brightness/contrast adjustment task.
Checks if brightness and contrast were improved appropriately using LAB color space analysis.
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

# Try to import skimage for LAB color space conversion
try:
    from skimage import color
    HAS_SKIMAGE = True
except ImportError:
    HAS_SKIMAGE = False
    logging.warning("scikit-image not available, using fallback RGB analysis")


def analyze_brightness_enhancement(original_img, result_img):
    """
    Analyze brightness improvement using LAB color space for perceptual accuracy.
    Falls back to RGB analysis if scikit-image is not available.
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Resize result to match original if needed
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    if HAS_SKIMAGE:
        # Use LAB color space for perceptually accurate brightness analysis
        try:
            # Convert to LAB color space (L* represents lightness)
            orig_lab = color.rgb2lab(orig_array / 255.0)
            result_lab = color.rgb2lab(result_array / 255.0)
            
            # Extract L* (lightness) channel
            orig_brightness = orig_lab[:, :, 0]
            result_brightness = result_lab[:, :, 0]
            
            # Calculate brightness change in LAB units
            brightness_change = np.mean(result_brightness) - np.mean(orig_brightness)
            
            # Calculate contrast change (standard deviation)
            contrast_change = np.std(result_brightness) - np.std(orig_brightness)
            
            return {
                'brightness_change': brightness_change,
                'contrast_change': contrast_change,
                'brightness_improved': 5 <= brightness_change <= 50,
                'contrast_improved': contrast_change >= 3,
                'analysis_method': 'LAB'
            }
            
        except Exception as e:
            logging.warning(f"LAB analysis failed: {e}, falling back to RGB")
            # Fall through to RGB analysis
    
    # Fallback RGB analysis
    # Convert to grayscale for brightness analysis
    orig_gray = np.dot(orig_array[...,:3], [0.2989, 0.5870, 0.1140])
    result_gray = np.dot(result_array[...,:3], [0.2989, 0.5870, 0.1140])
    
    # Calculate brightness change (mean luminance)
    brightness_change = np.mean(result_gray) - np.mean(orig_gray)
    
    # Calculate contrast change (standard deviation)
    contrast_change = np.std(result_gray) - np.std(orig_gray)
    
    # Scale to approximate LAB units (rough conversion)
    brightness_change_scaled = brightness_change * 0.4  # Approximate scaling factor
    contrast_change_scaled = contrast_change * 0.4
    
    return {
        'brightness_change': brightness_change_scaled,
        'contrast_change': contrast_change_scaled,
        'brightness_improved': 2 <= brightness_change_scaled <= 25,  # Lower thresholds for RGB
        'contrast_improved': contrast_change_scaled >= 1.5,
        'analysis_method': 'RGB_fallback'
    }


def detect_clipping(img_array, threshold=0.02):
    """
    Detect excessive highlight or shadow clipping.
    Returns True if clipping is within acceptable bounds.
    """
    # Convert to 0-255 range if needed
    if img_array.max() <= 1.0:
        img_array = img_array * 255
    
    total_pixels = img_array.size
    
    # Count pixels at extreme values
    clipped_highlights = np.sum(img_array >= 250)
    clipped_shadows = np.sum(img_array <= 5)
    
    # Calculate clipping percentage
    clipping_percentage = (clipped_highlights + clipped_shadows) / total_pixels
    
    return {
        'clipping_percentage': clipping_percentage,
        'acceptable_clipping': clipping_percentage < threshold,
        'highlight_pixels': clipped_highlights,
        'shadow_pixels': clipped_shadows
    }


def check_meaningful_change(original_img, result_img):
    """Check if the images are meaningfully different."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 20)  # Pixels with >20 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': mean_diff > 5 or change_percentage > 10
    }


def check_brightness_contrast(traj, env_info, task_info):
    """
    Main verifier function for brightness/contrast adjustment task.
    Checks:
    1. Brightness was meaningfully improved (5-50 LAB units)
    2. Contrast was enhanced (≥3 std dev increase)
    3. No excessive clipping occurred (<2% of pixels)
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
        "/home/ga/Desktop/enhanced_landscape.jpg",
        "/home/ga/Desktop/enhanced_landscape.png",
        "/home/ga/Desktop/enhanced_landscape.jpeg",
        "/home/ga/Desktop/underexposed_landscape_enhanced.jpg",
        "/home/ga/Desktop/landscape_enhanced.jpg"
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
        
        # Analyze brightness and contrast enhancement
        enhancement_analysis = analyze_brightness_enhancement(original_image, result_image)
        
        # Check for clipping
        result_array = np.array(result_image.convert('RGB'))
        clipping_analysis = detect_clipping(result_array)
        
        # Check for meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Analysis method: {enhancement_analysis['analysis_method']}")
        feedback_parts.append(f"Brightness change: {enhancement_analysis['brightness_change']:.2f}")
        feedback_parts.append(f"Contrast change: {enhancement_analysis['contrast_change']:.2f}")
        feedback_parts.append(f"Clipping: {clipping_analysis['clipping_percentage']:.2%}")
        feedback_parts.append(f"Change percentage: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Brightness improved appropriately
        if enhancement_analysis['brightness_improved']:
            criteria_met += 1
        feedback_parts.append(f"Brightness improved: {'✅' if enhancement_analysis['brightness_improved'] else '❌'}")
        
        # 2. Contrast enhanced
        if enhancement_analysis['contrast_improved']:
            criteria_met += 1
        feedback_parts.append(f"Contrast enhanced: {'✅' if enhancement_analysis['contrast_improved'] else '❌'}")
        
        # 3. No excessive clipping
        if clipping_analysis['acceptable_clipping']:
            criteria_met += 1
        feedback_parts.append(f"Clipping acceptable: {'✅' if clipping_analysis['acceptable_clipping'] else '❌'}")
        
        # 4. Meaningful change detected
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent brightness/contrast enhancement!")
        elif passed:
            feedback_parts.append("✅ Good brightness/contrast enhancement!")
        else:
            feedback_parts.append("❌ Enhancement needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in brightness/contrast verification: {e}")
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
    result = check_brightness_contrast([], {}, {})
    print(f"Test result: {result}")