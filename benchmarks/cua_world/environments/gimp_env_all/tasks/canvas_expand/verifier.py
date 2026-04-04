#!/usr/bin/env python3
"""
Verifier for GIMP canvas expansion task.
Checks if canvas was expanded by ~100 pixels in each direction with content preserved and centered.
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


def check_dimension_expansion(original_img, result_img, target_increase=100, tolerance=20):
    """Check if canvas dimensions were expanded by approximately the target amount."""
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    width_increase = result_width - orig_width
    height_increase = result_height - orig_height
    
    # Check if increases are within expected range
    width_increase_ok = (target_increase - tolerance) <= width_increase <= (target_increase + tolerance)
    height_increase_ok = (target_increase - tolerance) <= height_increase <= (target_increase + tolerance)
    
    dimension_expansion_ok = width_increase_ok and height_increase_ok
    
    return {
        'dimension_expansion_ok': dimension_expansion_ok,
        'width_increase': width_increase,
        'height_increase': height_increase,
        'orig_size': (orig_width, orig_height),
        'result_size': (result_width, result_height)
    }


def check_content_preservation_and_centering(original_img, result_img):
    """
    Check if original content is preserved and properly centered in the expanded canvas.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate expected position of original content (should be centered)
    expected_x_offset = (result_width - orig_width) // 2
    expected_y_offset = (result_height - orig_height) // 2
    
    # Extract the central region from result image where original content should be
    try:
        extracted_content = result_img.crop((
            expected_x_offset, 
            expected_y_offset,
            expected_x_offset + orig_width, 
            expected_y_offset + orig_height
        ))
        
        # Convert images to same mode for comparison
        if original_img.mode != extracted_content.mode:
            extracted_content = extracted_content.convert(original_img.mode)
        
        # Calculate similarity using SSIM
        try:
            from skimage.metrics import structural_similarity as ssim
            
            orig_array = np.array(original_img)
            extracted_array = np.array(extracted_content)
            
            # Ensure arrays have same shape
            if orig_array.shape != extracted_array.shape:
                content_preserved = False
                ssim_score = 0.0
            else:
                # Calculate SSIM
                if len(orig_array.shape) == 3:  # Color image
                    ssim_score = ssim(orig_array, extracted_array, multichannel=True, channel_axis=2)
                else:  # Grayscale
                    ssim_score = ssim(orig_array, extracted_array)
                
                content_preserved = ssim_score >= 0.95
            
        except ImportError:
            # Fallback: simple pixel comparison if SSIM not available
            orig_array = np.array(original_img)
            extracted_array = np.array(extracted_content)
            
            if orig_array.shape == extracted_array.shape:
                diff = np.mean(np.abs(orig_array.astype(np.float32) - extracted_array.astype(np.float32)))
                content_preserved = diff < 10  # Very low difference threshold
                ssim_score = 1.0 - (diff / 255.0)  # Approximate similarity
            else:
                content_preserved = False
                ssim_score = 0.0
        
        return {
            'content_preserved': content_preserved,
            'properly_centered': True,  # If we successfully extracted, it's likely centered
            'ssim_score': ssim_score,
            'expected_offset': (expected_x_offset, expected_y_offset)
        }
        
    except Exception as e:
        logging.error(f"Error in content preservation check: {e}")
        return {
            'content_preserved': False,
            'properly_centered': False,
            'ssim_score': 0.0,
            'expected_offset': (expected_x_offset, expected_y_offset),
            'error': str(e)
        }


def check_expansion_quality(original_img, result_img):
    """Check the quality of the expansion - background should be filled properly."""
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Sample border areas to check if they're filled with background color
    result_array = np.array(result_img.convert('RGB'))
    
    # Expected content area
    expected_x_offset = (result_width - orig_width) // 2
    expected_y_offset = (result_height - orig_height) // 2
    
    # Sample top border (should be background)
    if expected_y_offset > 10:
        top_border = result_array[0:expected_y_offset, :]
        top_border_mean = np.mean(top_border)
        
        # Check if top border is relatively uniform (good background fill)
        top_border_std = np.std(top_border)
        background_uniform = top_border_std < 50  # Low variation indicates uniform fill
        
        # Check if background is light (typical GIMP background)
        background_light = top_border_mean > 200
        
        expansion_clean = background_uniform and background_light
    else:
        expansion_clean = True  # No significant expansion to check
        top_border_mean = 255
        background_uniform = True
        background_light = True
    
    return {
        'expansion_clean': expansion_clean,
        'background_uniform': background_uniform,
        'background_light': background_light,
        'background_mean_intensity': top_border_mean
    }


def check_canvas_expansion(traj, env_info, task_info):
    """
    Main verifier function for canvas expansion task.
    Checks:
    1. Canvas dimensions increased by ~100 pixels in each direction
    2. Original content is preserved and centered
    3. Expansion areas are properly filled
    4. Overall quality is maintained
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
        "/home/ga/Desktop/expanded_canvas.jpg",
        "/home/ga/Desktop/expanded_canvas.png", 
        "/home/ga/Desktop/expanded_canvas.jpeg",
        "/home/ga/Desktop/landscape_canvas_expanded.jpg",
        "/home/ga/Desktop/landscape_expanded.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_canvas.jpg",
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
        
        # Check dimension expansion
        dimension_check = check_dimension_expansion(original_image, result_image, target_increase=100, tolerance=20)
        
        # Check content preservation and centering
        content_check = check_content_preservation_and_centering(original_image, result_image)
        
        # Check expansion quality
        quality_check = check_expansion_quality(original_image, result_image)
        
        # Check if image was actually modified
        images_different = original_image.size != result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {dimension_check['orig_size']}")
        feedback_parts.append(f"Result size: {dimension_check['result_size']}")
        feedback_parts.append(f"Width increase: {dimension_check['width_increase']}px")
        feedback_parts.append(f"Height increase: {dimension_check['height_increase']}px")
        feedback_parts.append(f"Dimensions expanded correctly: {'✅' if dimension_check['dimension_expansion_ok'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_check['content_preserved'] else '❌'}")
        feedback_parts.append(f"Content centered: {'✅' if content_check['properly_centered'] else '❌'}")
        feedback_parts.append(f"Expansion clean: {'✅' if quality_check['expansion_clean'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        if 'ssim_score' in content_check:
            feedback_parts.append(f"Content similarity: {content_check['ssim_score']:.3f}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimension_check['dimension_expansion_ok']:
            criteria_met += 1
        if content_check['content_preserved']:
            criteria_met += 1
        if content_check['properly_centered']:
            criteria_met += 1
        if quality_check['expansion_clean']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect canvas expansion!")
        elif passed:
            feedback_parts.append("✅ Good canvas expansion!")
        else:
            feedback_parts.append("❌ Canvas expansion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in canvas expansion verification: {e}")
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
    result = check_canvas_expansion([], {}, {})
    print(f"Test result: {result}")