#!/usr/bin/env python3
"""
Verifier for GIMP drop shadow task.
Checks if a drop shadow effect was successfully applied to the object image.
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


def detect_drop_shadow(original_img, result_img):
    """
    Detect drop shadow by analyzing luminance changes.
    Returns shadow detection metrics and statistics.
    """
    # Ensure images are same size for comparison
    if result_img.size != original_img.size:
        # Shadow might extend canvas, so we need to handle size differences
        orig_width, orig_height = original_img.size
        result_width, result_height = result_img.size
        
        # If result is larger (canvas extended for shadow), crop original region for comparison
        if result_width >= orig_width and result_height >= orig_height:
            # Extract the original region from result image (typically top-left)
            original_region = result_img.crop((0, 0, orig_width, orig_height))
            # Compare with original to see if the main subject is preserved
            # For shadow detection, we need to analyze the full result image
            pass
        else:
            # If result is smaller or different, resize for comparison
            result_img = result_img.resize(original_img.size)
    
    # Convert to grayscale for luminance analysis
    if original_img.mode != 'L':
        orig_gray = np.array(original_img.convert('L')).astype(np.float32)
    else:
        orig_gray = np.array(original_img).astype(np.float32)
    
    if result_img.mode != 'L':
        result_gray = np.array(result_img.convert('L')).astype(np.float32)
    else:
        result_gray = np.array(result_img).astype(np.float32)
    
    # Handle size differences - pad original if result is larger
    if result_gray.shape != orig_gray.shape:
        if result_gray.size > orig_gray.size:
            # Pad original with white background to match result size
            padded_orig = np.full(result_gray.shape, 255.0, dtype=np.float32)
            padded_orig[:orig_gray.shape[0], :orig_gray.shape[1]] = orig_gray
            orig_gray = padded_orig
        else:
            # Crop result to match original size
            result_gray = result_gray[:orig_gray.shape[0], :orig_gray.shape[1]]
    
    # Calculate luminance difference (original - result)
    # Positive values indicate areas that became darker (potential shadow)
    luminance_diff = orig_gray - result_gray
    
    # Identify significantly darkened regions (potential shadow areas)
    shadow_threshold = 20  # Pixels that became at least 20 units darker
    shadow_mask = luminance_diff > shadow_threshold
    
    # Calculate shadow statistics
    total_pixels = shadow_mask.size
    shadow_pixels = np.sum(shadow_mask)
    shadow_area_percentage = (shadow_pixels / total_pixels) * 100
    
    # Calculate overall luminance change
    mean_luminance_change = (np.mean(orig_gray) - np.mean(result_gray)) / np.mean(orig_gray) if np.mean(orig_gray) > 0 else 0
    luminance_decrease_percentage = mean_luminance_change * 100
    
    # Check shadow opacity (shadows shouldn't be pure black)
    if shadow_pixels > 0:
        shadow_pixel_values = result_gray[shadow_mask]
        min_shadow_brightness = np.min(shadow_pixel_values)
        mean_shadow_brightness = np.mean(shadow_pixel_values)
        proper_opacity = min_shadow_brightness > 20 and mean_shadow_brightness > 40
    else:
        proper_opacity = False
        min_shadow_brightness = 255
        mean_shadow_brightness = 255
    
    # Detect if shadow is appropriately positioned (typically bottom-right)
    height, width = shadow_mask.shape
    bottom_right_quadrant = shadow_mask[height//2:, width//2:]
    shadow_in_bottom_right = np.sum(bottom_right_quadrant) > shadow_pixels * 0.3  # At least 30% of shadow in bottom-right
    
    return {
        'shadow_area_percentage': shadow_area_percentage,
        'luminance_decrease_percentage': abs(luminance_decrease_percentage),
        'proper_opacity': proper_opacity,
        'min_shadow_brightness': min_shadow_brightness,
        'mean_shadow_brightness': mean_shadow_brightness,
        'shadow_in_bottom_right': shadow_in_bottom_right,
        'total_shadow_pixels': shadow_pixels,
        'shadow_detected': shadow_area_percentage >= 5  # At least 5% shadow area
    }


def check_meaningful_image_change(original_img, result_img):
    """Check if the images are meaningfully different (shadow was added)."""
    # Handle size differences
    if result_img.size != original_img.size:
        # If result is larger, shadow likely extended the canvas
        orig_width, orig_height = original_img.size
        result_width, result_height = result_img.size
        if result_width > orig_width or result_height > orig_height:
            # This itself indicates shadow was added (canvas extension)
            return True, f"Canvas extended from {original_img.size} to {result_img.size}"
        else:
            # Resize for comparison
            result_img = result_img.resize(original_img.size)
    
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Calculate pixel differences
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    if len(diff.shape) == 3:  # Color image
        # Calculate magnitude of change per pixel
        pixel_diff_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        pixel_diff_magnitude = diff
    
    # Count significantly changed pixels
    significantly_changed = np.sum(pixel_diff_magnitude > 30)  # >30 intensity units change
    total_pixels = pixel_diff_magnitude.size
    change_percentage = (significantly_changed / total_pixels) * 100
    
    meaningful_change = change_percentage > 5  # At least 5% of pixels changed significantly
    
    return meaningful_change, f"Changed pixels: {change_percentage:.1f}%"


def check_drop_shadow(traj, env_info, task_info):
    """
    Main verifier function for drop shadow task.
    Checks:
    1. Shadow regions detected through luminance analysis
    2. Shadow has proper opacity (not pure black)
    3. Shadow covers appropriate area (5-30% of image)
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
        "/home/ga/Desktop/object_with_shadow.png",
        "/home/ga/Desktop/object_with_shadow.jpg",
        "/home/ga/Desktop/object_with_shadow.jpeg",
        "/home/ga/Desktop/shadow_object.png",
        "/home/ga/Desktop/object_image_shadow.png",
        "/home/ga/Desktop/object_image_edited.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/object_image.png",
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
        
        # Detect drop shadow
        shadow_analysis = detect_drop_shadow(original_image, result_image)
        
        # Check for meaningful change
        meaningful_change, change_details = check_meaningful_image_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Shadow area: {shadow_analysis['shadow_area_percentage']:.1f}%")
        feedback_parts.append(f"Luminance decrease: {shadow_analysis['luminance_decrease_percentage']:.1f}%")
        feedback_parts.append(f"Min shadow brightness: {shadow_analysis['min_shadow_brightness']:.0f}")
        feedback_parts.append(f"Mean shadow brightness: {shadow_analysis['mean_shadow_brightness']:.0f}")
        feedback_parts.append(change_details)
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Shadow darkness - overall luminance should decrease by 10-30%
        shadow_darkness_good = 10 <= shadow_analysis['luminance_decrease_percentage'] <= 30
        if shadow_darkness_good:
            criteria_met += 1
        feedback_parts.append(f"Good shadow darkness: {'✅' if shadow_darkness_good else '❌'}")
        
        # 2. Shadow coverage - should occupy 5-30% of image area
        shadow_coverage_good = 5 <= shadow_analysis['shadow_area_percentage'] <= 30
        if shadow_coverage_good:
            criteria_met += 1
        feedback_parts.append(f"Appropriate shadow size: {'✅' if shadow_coverage_good else '❌'}")
        
        # 3. Proper opacity - shadow regions shouldn't be pure black
        if shadow_analysis['proper_opacity']:
            criteria_met += 1
        feedback_parts.append(f"Proper shadow opacity: {'✅' if shadow_analysis['proper_opacity'] else '❌'}")
        
        # 4. Image was meaningfully modified
        if meaningful_change:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if meaningful_change else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent drop shadow applied!")
        elif passed:
            feedback_parts.append("✅ Good drop shadow effect!")
        else:
            feedback_parts.append("❌ Drop shadow needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in drop shadow verification: {e}")
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
    result = check_drop_shadow([], {}, {})
    print(f"Test result: {result}")