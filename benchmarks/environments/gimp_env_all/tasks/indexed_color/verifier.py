#!/usr/bin/env python3
"""
Verifier for GIMP indexed color conversion task.
Checks if image was converted from RGB to indexed color mode with reduced palette.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

# Set up logging
logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def analyze_image_mode_and_colors(img):
    """
    Analyze image color mode and count unique colors.
    Returns mode, color count, and analysis details.
    """
    mode = img.mode
    
    # Convert to array for color analysis
    if mode == 'P':  # Palette/Indexed mode
        # For palette mode, count unique palette indices
        img_array = np.array(img)
        unique_colors = len(np.unique(img_array))
        palette_size = len(img.getpalette()) // 3 if img.getpalette() else 0
        
        return {
            'mode': mode,
            'unique_colors': unique_colors,
            'palette_size': palette_size,
            'is_indexed': True
        }
    else:
        # For RGB/other modes, count unique RGB combinations
        if mode != 'RGB':
            img = img.convert('RGB')
        img_array = np.array(img)
        # Reshape to list of RGB triplets and find unique combinations
        pixels = img_array.reshape(-1, 3)
        unique_pixels = np.unique(pixels, axis=0)
        unique_colors = len(unique_pixels)
        
        return {
            'mode': mode,
            'unique_colors': unique_colors,
            'palette_size': 0,
            'is_indexed': False
        }


def check_posterization_effect(original_img, result_img):
    """
    Check if the image shows posterization (color banding) typical of indexed conversion.
    """
    # Convert both to RGB for comparison
    if original_img.mode != 'RGB':
        original_rgb = original_img.convert('RGB')
    else:
        original_rgb = original_img
    
    if result_img.mode != 'RGB':
        result_rgb = result_img.convert('RGB') 
    else:
        result_rgb = result_img
    
    # Ensure same size for comparison
    if original_rgb.size != result_rgb.size:
        result_rgb = result_rgb.resize(original_rgb.size)
    
    orig_array = np.array(original_rgb)
    result_array = np.array(result_rgb)
    
    # Calculate color variance in both images
    orig_variance = np.var(orig_array)
    result_variance = np.var(result_array)
    
    # Check for significant difference (should be reduced due to color quantization)
    variance_ratio = result_variance / (orig_variance + 1e-8)  # Avoid division by zero
    
    # Calculate histogram differences to detect color reduction
    orig_hist = np.histogram(orig_array, bins=256, range=(0, 256))[0]
    result_hist = np.histogram(result_array, bins=256, range=(0, 256))[0]
    
    # Count non-zero histogram bins (indicates color complexity)
    orig_color_bins = np.sum(orig_hist > 0)
    result_color_bins = np.sum(result_hist > 0)
    
    return {
        'variance_ratio': variance_ratio,
        'orig_color_bins': orig_color_bins,
        'result_color_bins': result_color_bins,
        'color_reduction': orig_color_bins > result_color_bins
    }


def check_indexed_conversion(traj, env_info, task_info):
    """
    Main verifier function for indexed color conversion task.
    Checks:
    1. Image mode is 'P' (Palette/Indexed)
    2. Color count is reduced to approximately 16 (8-32 range)
    3. Image shows posterization effect
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
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container paths - try different possible output formats
        possible_results = [
            "/home/ga/Desktop/indexed_image.png",
            "/home/ga/Desktop/indexed_image.gif",
            "/home/ga/Desktop/indexed_image.jpg", 
            "/home/ga/Desktop/indexed_image.jpeg",
            "/home/ga/Desktop/colorful_image_indexed.png",
            "/home/ga/Desktop/colorful_indexed.png"
        ]
        
        container_original = "/home/ga/Desktop/colorful_image.jpg"
        
        # Define host paths
        host_original = temp_path / "original.jpg"
        host_result = temp_path / "result.png"
        
        # Try to copy original image from container
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original image: {error}"
            }
        
        # Try to copy result image from container (try multiple possible names)
        result_found = False
        result_container_path = None
        for result_path in possible_results:
            success, error = copy_file_from_container(copy_from_env, result_path, host_result)
            if success:
                result_found = True
                result_container_path = result_path
                logging.debug(f"Found result image at: {result_path}")
                break
        
        if not result_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result image. Tried: {[Path(p).name for p in possible_results]}"
            }
        
        try:
            # Load images from copied files
            original_image = Image.open(host_original)
            result_image = Image.open(host_result)
            
            logging.debug(f"Found result image at: {result_container_path}")
            
            # Analyze original and result images
            original_analysis = analyze_image_mode_and_colors(original_image)
            result_analysis = analyze_image_mode_and_colors(result_image)
            
            # Check posterization effect
            posterization = check_posterization_effect(original_image, result_image)
            
            # Check if images are different
            images_different = (original_image.size != result_image.size or 
                              original_analysis['mode'] != result_analysis['mode'] or
                              original_analysis['unique_colors'] != result_analysis['unique_colors'])
            
            feedback_parts = []
            feedback_parts.append(f"Original mode: {original_analysis['mode']}")
            feedback_parts.append(f"Result mode: {result_analysis['mode']}")
            feedback_parts.append(f"Original colors: {original_analysis['unique_colors']}")
            feedback_parts.append(f"Result colors: {result_analysis['unique_colors']}")
            
            # Evaluate success criteria
            criteria_met = 0
            total_criteria = 4
            
            # 1. Image mode is 'P' (Indexed/Palette)
            mode_converted = result_analysis['is_indexed']
            if mode_converted:
                criteria_met += 1
            feedback_parts.append(f"Converted to indexed mode: {'✅' if mode_converted else '❌'}")
            
            # 2. Color count is in target range (8-32 colors, target ~16)
            target_colors = 8 <= result_analysis['unique_colors'] <= 32
            if target_colors:
                criteria_met += 1
            feedback_parts.append(f"Colors in target range (8-32): {'✅' if target_colors else '❌'}")
            
            # 3. Posterization/color reduction effect detected
            posterization_detected = (posterization['color_reduction'] or 
                                    result_analysis['unique_colors'] < original_analysis['unique_colors'] * 0.5)
            if posterization_detected:
                criteria_met += 1
            feedback_parts.append(f"Color reduction detected: {'✅' if posterization_detected else '❌'}")
            
            # 4. Image was modified
            if images_different:
                criteria_met += 1
            feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
            
            # Calculate score and pass/fail
            score = int((criteria_met / total_criteria) * 100)
            passed = score >= 75  # Need at least 3/4 criteria
            
            # Additional details for debugging
            if result_analysis['is_indexed']:
                feedback_parts.append(f"Palette size: {result_analysis['palette_size']}")
            
            feedback_parts.append(f"Variance ratio: {posterization['variance_ratio']:.2f}")
            
            if passed and score >= 90:
                feedback_parts.append("🎉 Perfect indexed color conversion!")
            elif passed:
                feedback_parts.append("✅ Good indexed color conversion!")
            else:
                feedback_parts.append("❌ Indexed color conversion needs improvement")
                
            return {
                "passed": passed,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        except Exception as e:
            logging.error(f"Error in indexed color verification: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: {str(e)}"
            }


if __name__ == "__main__":
    # Test the verifier
    result = check_indexed_conversion([], {}, {})
    print(f"Test result: {result}")