#!/usr/bin/env python3
"""
Verifier for GIMP border addition task.
Checks if a border was properly added around the image by expanding canvas and filling with color.
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


def detect_border_addition(original_img, result_img):
    """
    Analyze if a border was properly added by detecting dimension changes and color patterns.
    """
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Check for size increase
    width_increase = result_w - orig_w
    height_increase = result_h - orig_h
    
    analysis = {
        'width_increase': width_increase,
        'height_increase': height_increase,
        'size_increased': width_increase >= 20 and height_increase >= 20,  # At least 20px total increase
        'proportional_increase': abs(width_increase - height_increase) <= 10,  # Roughly equal increases
        'meaningful_border': False,
        'border_coverage': 0
    }
    
    if not analysis['size_increased']:
        return analysis
    
    # Analyze border regions for uniform color
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    result_array = np.array(result_img)
    
    # Calculate expected border width (assuming centered expansion)
    border_w = width_increase // 2
    border_h = height_increase // 2
    
    if border_w < 5 or border_h < 5:  # Too small to analyze meaningfully
        return analysis
    
    # Extract border regions
    top_border = result_array[:border_h, :] if border_h > 0 else np.array([])
    bottom_border = result_array[-border_h:, :] if border_h > 0 else np.array([])
    left_border = result_array[:, :border_w] if border_w > 0 else np.array([])
    right_border = result_array[:, -border_w:] if border_w > 0 else np.array([])
    
    border_regions = [r for r in [top_border, bottom_border, left_border, right_border] if r.size > 0]
    
    if not border_regions:
        return analysis
    
    # Check for uniform border color (expecting white or light color)
    uniform_regions = 0
    total_regions = len(border_regions)
    
    for region in border_regions:
        if region.size == 0:
            continue
            
        # Calculate color statistics for this border region
        region_colors = region.reshape(-1, 3)
        mean_color = np.mean(region_colors, axis=0)
        color_std = np.std(region_colors, axis=0)
        
        # Check if region is uniformly colored (low standard deviation)
        # and uses a light color (high mean values)
        is_uniform = np.all(color_std < 30)  # Low variation in each channel
        is_light = np.mean(mean_color) > 200  # Bright/white color
        
        if is_uniform and is_light:
            uniform_regions += 1
            logging.debug(f"Found uniform light border region: mean={mean_color}, std={color_std}")
    
    analysis['meaningful_border'] = uniform_regions >= (total_regions * 0.75)  # At least 75% of borders uniform
    analysis['border_coverage'] = uniform_regions / total_regions if total_regions > 0 else 0
    
    return analysis


def check_content_preservation(original_img, result_img, border_analysis):
    """
    Check if the original image content is preserved in the center of the result.
    """
    if not border_analysis['size_increased']:
        return False, 0.0
    
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Calculate expected position of original content in result
    border_w = (result_w - orig_w) // 2
    border_h = (result_h - orig_h) // 2
    
    # Extract center region from result that should match original
    try:
        center_region = result_img.crop((
            border_w, border_h, 
            border_w + orig_w, border_h + orig_h
        ))
        
        if center_region.size != original_img.size:
            return False, 0.0
        
        # Use structural similarity to compare
        try:
            from skimage.metrics import structural_similarity as ssim
            
            # Convert to same mode for comparison
            orig_array = np.array(original_img.convert('RGB'))
            center_array = np.array(center_region.convert('RGB'))
            
            if orig_array.shape != center_array.shape:
                return False, 0.0
            
            # Calculate SSIM for each channel and take mean
            ssim_score = ssim(orig_array, center_array, multichannel=True, channel_axis=2)
            
            content_preserved = ssim_score >= 0.95  # Very high similarity required
            return content_preserved, ssim_score
            
        except ImportError:
            # Fallback: simple pixel difference check
            orig_array = np.array(original_img.convert('RGB'))
            center_array = np.array(center_region.convert('RGB'))
            
            if orig_array.shape != center_array.shape:
                return False, 0.0
            
            # Calculate mean absolute difference
            diff = np.mean(np.abs(orig_array.astype(np.float32) - center_array.astype(np.float32)))
            similarity = max(0, 1 - (diff / 255))  # Normalize to 0-1 range
            
            content_preserved = similarity >= 0.95
            return content_preserved, similarity
            
    except Exception as e:
        logging.error(f"Error in content preservation check: {e}")
        return False, 0.0


def check_border_addition(traj, env_info, task_info):
    """
    Main verifier function for border addition task.
    Checks:
    1. Image dimensions increased significantly (border space added)
    2. Original image content preserved in center 
    3. Border regions filled with uniform color
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
        "/home/ga/Desktop/bordered_image.jpg",
        "/home/ga/Desktop/bordered_image.png", 
        "/home/ga/Desktop/bordered_image.jpeg",
        "/home/ga/Desktop/portrait_image_bordered.jpg",
        "/home/ga/Desktop/portrait_with_border.jpg",
        "/home/ga/Desktop/canvas_expanded.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/portrait_image.jpg",
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
        
        # Analyze border addition
        border_analysis = detect_border_addition(original_image, result_image)
        
        # Check content preservation
        content_preserved, similarity_score = check_content_preservation(original_image, result_image, border_analysis)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size or not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Size increase: {border_analysis['width_increase']}x{border_analysis['height_increase']}")
        feedback_parts.append(f"Dimensions increased: {'✅' if border_analysis['size_increased'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_preserved else '❌'} (SSIM: {similarity_score:.3f})")
        feedback_parts.append(f"Border coverage: {border_analysis['border_coverage']:.1%}")
        feedback_parts.append(f"Uniform border: {'✅' if border_analysis['meaningful_border'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if border_analysis['size_increased']:
            criteria_met += 1
        if content_preserved:
            criteria_met += 1 
        if border_analysis['meaningful_border']:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect border addition!")
        elif passed:
            feedback_parts.append("✅ Good border addition!")
        else:
            feedback_parts.append("❌ Border addition needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in border addition verification: {e}")
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
    result = check_border_addition([], {}, {})
    print(f"Test result: {result}")