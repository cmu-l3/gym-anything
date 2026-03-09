#!/usr/bin/env python3
"""
Verifier for GIMP print resolution task.
Checks if image DPI was changed to 300 without altering pixel dimensions.
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


def extract_dpi_info(img):
    """
    Extract DPI information from image, handling various formats and storage methods.
    Returns (x_dpi, y_dpi) or (None, None) if not found.
    """
    try:
        # Method 1: Check 'dpi' key in image info
        if 'dpi' in img.info:
            dpi_info = img.info['dpi']
            if isinstance(dpi_info, (tuple, list)) and len(dpi_info) >= 2:
                return float(dpi_info[0]), float(dpi_info[1])
            elif isinstance(dpi_info, (int, float)):
                return float(dpi_info), float(dpi_info)
        
        # Method 2: Check 'resolution' key
        if 'resolution' in img.info:
            res_info = img.info['resolution']
            if isinstance(res_info, (tuple, list)) and len(res_info) >= 2:
                return float(res_info[0]), float(res_info[1])
        
        # Method 3: Check EXIF data for resolution
        if hasattr(img, '_getexif'):
            exif = img._getexif()
            if exif:
                # EXIF tags: XResolution=282, YResolution=283, ResolutionUnit=296
                x_res = exif.get(282)  # XResolution
                y_res = exif.get(283)  # YResolution
                unit = exif.get(296, 2)  # ResolutionUnit (2=inches, 3=cm)
                
                if x_res and y_res:
                    # Convert fraction to float if needed
                    if hasattr(x_res, '__len__'):  # It's a fraction
                        x_dpi = float(x_res[0]) / float(x_res[1])
                    else:
                        x_dpi = float(x_res)
                    
                    if hasattr(y_res, '__len__'):  # It's a fraction
                        y_dpi = float(y_res[0]) / float(y_res[1])
                    else:
                        y_dpi = float(y_res)
                    
                    # Convert from cm to inches if needed
                    if unit == 3:
                        x_dpi *= 2.54
                        y_dpi *= 2.54
                    
                    return x_dpi, y_dpi
        
        # Default if no DPI info found
        return None, None
        
    except Exception as e:
        logging.warning(f"Error extracting DPI info: {e}")
        return None, None


def check_dpi_change(original_img, result_img, target_dpi=300):
    """
    Check if DPI was changed appropriately.
    Returns dict with analysis results.
    """
    # Extract DPI from both images
    orig_x_dpi, orig_y_dpi = extract_dpi_info(original_img)
    result_x_dpi, result_y_dpi = extract_dpi_info(result_img)
    
    analysis = {
        'original_dpi': (orig_x_dpi, orig_y_dpi),
        'result_dpi': (result_x_dpi, result_y_dpi),
        'target_dpi': target_dpi,
        'dpi_extracted': False,
        'dpi_changed': False,
        'target_achieved': False,
        'reasonable_value': False,
        'dimensions_preserved': False
    }
    
    # Check if we could extract DPI from result image
    if result_x_dpi is not None and result_y_dpi is not None:
        analysis['dpi_extracted'] = True
        
        # Check if DPI changed from original (if we have original DPI)
        if orig_x_dpi is not None and orig_y_dpi is not None:
            orig_avg = (orig_x_dpi + orig_y_dpi) / 2
            result_avg = (result_x_dpi + result_y_dpi) / 2
            analysis['dpi_changed'] = abs(result_avg - orig_avg) > 20
        else:
            # If we don't have original DPI, assume it was default 72
            result_avg = (result_x_dpi + result_y_dpi) / 2
            analysis['dpi_changed'] = abs(result_avg - 72) > 20
        
        # Check if target DPI achieved (with tolerance)
        x_close = abs(result_x_dpi - target_dpi) <= 10
        y_close = abs(result_y_dpi - target_dpi) <= 10
        analysis['target_achieved'] = x_close and y_close
        
        # Check if DPI is in reasonable range
        result_avg = (result_x_dpi + result_y_dpi) / 2
        analysis['reasonable_value'] = 100 <= result_avg <= 600
    
    # Check if pixel dimensions were preserved
    analysis['dimensions_preserved'] = (original_img.size == result_img.size)
    
    return analysis


def check_pixel_integrity(original_img, result_img):
    """
    Check if pixel data was preserved (no actual image scaling occurred).
    """
    if original_img.size != result_img.size:
        return False, f"Dimensions changed: {original_img.size} → {result_img.size}"
    
    # Convert to same format for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Compare pixel data (allowing for minor JPEG compression differences)
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate mean absolute difference
    pixel_diff = np.mean(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)))
    
    # Allow small differences due to JPEG compression artifacts
    pixels_preserved = pixel_diff < 5  # Very small tolerance for compression
    
    return pixels_preserved, f"Pixel difference: {pixel_diff:.2f}"


def check_print_resolution(traj, env_info, task_info):
    """
    Main verifier function for print resolution task.
    Checks:
    1. DPI metadata was changed to 300 (±10 tolerance)
    2. Pixel dimensions were exactly preserved
    3. DPI value is reasonable for print (100-600 range)
    4. Image was actually modified from original
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
        "/home/ga/Desktop/landscape_300dpi.jpg",
        "/home/ga/Desktop/landscape_300dpi.png", 
        "/home/ga/Desktop/landscape_300dpi.jpeg",
        "/home/ga/Desktop/landscape_image_300dpi.jpg",
        "/home/ga/Desktop/landscape_modified.jpg"
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
        
        # Analyze DPI changes
        dpi_analysis = check_dpi_change(original_image, result_image, 300)
        
        # Check pixel integrity
        pixels_preserved, pixel_info = check_pixel_integrity(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        
        # Report DPI information
        orig_dpi = dpi_analysis['original_dpi']
        result_dpi = dpi_analysis['result_dpi']
        
        if orig_dpi[0] is not None:
            feedback_parts.append(f"Original DPI: {orig_dpi[0]:.1f}×{orig_dpi[1]:.1f}")
        else:
            feedback_parts.append("Original DPI: Not found (likely 72)")
            
        if result_dpi[0] is not None:
            feedback_parts.append(f"Result DPI: {result_dpi[0]:.1f}×{result_dpi[1]:.1f}")
        else:
            feedback_parts.append("Result DPI: Not found")
        
        feedback_parts.append(f"Target DPI: 300")
        feedback_parts.append(f"DPI extracted: {'✅' if dpi_analysis['dpi_extracted'] else '❌'}")
        feedback_parts.append(f"DPI changed: {'✅' if dpi_analysis['dpi_changed'] else '❌'}")
        feedback_parts.append(f"Target achieved (±10): {'✅' if dpi_analysis['target_achieved'] else '❌'}")
        feedback_parts.append(f"Reasonable value: {'✅' if dpi_analysis['reasonable_value'] else '❌'}")
        feedback_parts.append(f"Dimensions preserved: {'✅' if pixels_preserved else '❌'}")
        feedback_parts.append(pixel_info)
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        if dpi_analysis['dpi_extracted']:
            criteria_met += 1
        if dpi_analysis['target_achieved']:
            criteria_met += 1
        if dpi_analysis['reasonable_value']:
            criteria_met += 1
        if dpi_analysis['dpi_changed']:
            criteria_met += 1
        if pixels_preserved:
            criteria_met += 1
        
        # Score based on criteria met and precision
        score = int((criteria_met / total_criteria) * 100)
        
        # Bonus for perfect DPI match
        if (result_dpi[0] is not None and result_dpi[1] is not None and
            abs(result_dpi[0] - 300) <= 5 and abs(result_dpi[1] - 300) <= 5 and
            pixels_preserved):
            score = 100
        
        passed = score >= 75  # Need at least 4/5 criteria or very close to target
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect print resolution change!")
        elif passed:
            feedback_parts.append("✅ Good print resolution change!")
        else:
            feedback_parts.append("❌ Print resolution change needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in print resolution verification: {e}")
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
    result = check_print_resolution([], {}, {})
    print(f"Test result: {result}")