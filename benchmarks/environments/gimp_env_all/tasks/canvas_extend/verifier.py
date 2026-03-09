#!/usr/bin/env python3
"""
Verifier for GIMP canvas extension task.
Checks if canvas was extended by 200px width and 150px height with original content centered.
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

try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    # Fallback for older versions
    try:
        from skimage.measure import compare_ssim as ssim
    except ImportError:
        ssim = None
        logging.warning("SSIM not available - using basic comparison")


def verify_canvas_dimensions(original_img, result_img, target_width_increase=200, target_height_increase=150, tolerance=10):
    """
    Verify that canvas dimensions increased by the specified amounts within tolerance.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate actual increases
    width_increase = result_width - orig_width
    height_increase = result_height - orig_height
    
    # Check if increases are within tolerance of target
    width_correct = abs(width_increase - target_width_increase) <= tolerance
    height_correct = abs(height_increase - target_height_increase) <= tolerance
    
    return {
        'dimensions_correct': width_correct and height_correct,
        'original_size': (orig_width, orig_height),
        'result_size': (result_width, result_height),
        'width_increase': width_increase,
        'height_increase': height_increase,
        'width_target': target_width_increase,
        'height_target': target_height_increase
    }


def verify_content_preservation(original_img, result_img):
    """
    Verify that original content is preserved and properly centered in the result.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate expected center position offset
    expected_offset_x = (result_width - orig_width) // 2
    expected_offset_y = (result_height - orig_height) // 2
    
    # Extract the center region from result image
    try:
        # Convert images to same mode for comparison
        if original_img.mode != result_img.mode:
            if original_img.mode == 'RGB':
                result_img = result_img.convert('RGB')
            elif result_img.mode == 'RGB':
                original_img = original_img.convert('RGB')
        
        # Extract center region
        center_region = result_img.crop((
            expected_offset_x, 
            expected_offset_y, 
            expected_offset_x + orig_width, 
            expected_offset_y + orig_height
        ))
        
        # Compare original with extracted center using SSIM if available
        if ssim is not None:
            orig_array = np.array(original_img)
            center_array = np.array(center_region)
            
            # Ensure arrays have same shape
            if orig_array.shape != center_array.shape:
                logging.debug(f"Shape mismatch: {orig_array.shape} vs {center_array.shape}")
                return {'content_preserved': False, 'similarity': 0.0, 'method': 'shape_mismatch'}
            
            # Calculate SSIM
            try:
                if len(orig_array.shape) == 3:  # Color image
                    try:
                        similarity = ssim(orig_array, center_array, multichannel=True, channel_axis=2)
                    except TypeError:
                        similarity = ssim(orig_array, center_array, multichannel=True)
                else:  # Grayscale
                    similarity = ssim(orig_array, center_array)
                
                preserved = similarity >= 0.85  # High threshold for content preservation
                return {'content_preserved': preserved, 'similarity': similarity, 'method': 'ssim'}
                
            except Exception as e:
                logging.debug(f"SSIM failed: {e}, falling back to pixel comparison")
        
        # Fallback: Simple pixel difference comparison
        orig_array = np.array(original_img.convert('RGB'))
        center_array = np.array(center_region.convert('RGB'))
        
        if orig_array.shape == center_array.shape:
            # Calculate mean absolute difference
            diff = np.mean(np.abs(orig_array.astype(np.float32) - center_array.astype(np.float32)))
            similarity = 1.0 - (diff / 255.0)  # Normalize to 0-1 range
            preserved = similarity >= 0.90  # High threshold for pixel comparison
            
            return {'content_preserved': preserved, 'similarity': similarity, 'method': 'pixel_diff'}
        else:
            return {'content_preserved': False, 'similarity': 0.0, 'method': 'size_mismatch'}
            
    except Exception as e:
        logging.error(f"Content preservation check failed: {e}")
        return {'content_preserved': False, 'similarity': 0.0, 'method': 'error'}


def detect_canvas_borders(original_img, result_img):
    """
    Detect new canvas areas (borders) around the original content.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Check if canvas actually expanded
    if result_width <= orig_width or result_height <= orig_height:
        return {'borders_detected': False, 'border_info': 'No size increase detected'}
    
    try:
        result_array = np.array(result_img.convert('RGB'))
        
        # Calculate expected border sizes
        width_increase = result_width - orig_width
        height_increase = result_height - orig_height
        
        left_border_width = width_increase // 2
        right_border_width = width_increase - left_border_width
        top_border_height = height_increase // 2
        bottom_border_height = height_increase - top_border_height
        
        # Sample border regions (use smaller regions to avoid sampling original content)
        sample_size = min(30, min(left_border_width, top_border_height, right_border_width, bottom_border_height))
        
        if sample_size < 5:
            return {'borders_detected': False, 'border_info': 'Border regions too small to analyze'}
        
        # Extract border samples
        borders_found = 0
        border_uniformity_scores = []
        
        # Top border
        if top_border_height > 5:
            top_sample = result_array[:sample_size, sample_size:-sample_size] if sample_size < result_width//2 else result_array[:sample_size, :]
            if top_sample.size > 0:
                top_std = np.std(top_sample)
                border_uniformity_scores.append(top_std)
                if top_std < 40:  # Relatively uniform
                    borders_found += 1
        
        # Bottom border
        if bottom_border_height > 5:
            bottom_sample = result_array[-sample_size:, sample_size:-sample_size] if sample_size < result_width//2 else result_array[-sample_size:, :]
            if bottom_sample.size > 0:
                bottom_std = np.std(bottom_sample)
                border_uniformity_scores.append(bottom_std)
                if bottom_std < 40:  # Relatively uniform
                    borders_found += 1
        
        # Left border
        if left_border_width > 5:
            left_sample = result_array[sample_size:-sample_size, :sample_size] if sample_size < result_height//2 else result_array[:, :sample_size]
            if left_sample.size > 0:
                left_std = np.std(left_sample)
                border_uniformity_scores.append(left_std)
                if left_std < 40:  # Relatively uniform
                    borders_found += 1
        
        # Right border
        if right_border_width > 5:
            right_sample = result_array[sample_size:-sample_size, -sample_size:] if sample_size < result_height//2 else result_array[:, -sample_size:]
            if right_sample.size > 0:
                right_std = np.std(right_sample)
                border_uniformity_scores.append(right_std)
                if right_std < 40:  # Relatively uniform
                    borders_found += 1
        
        # Consider borders detected if at least 2 regions show uniform characteristics
        borders_detected = borders_found >= 2
        avg_uniformity = np.mean(border_uniformity_scores) if border_uniformity_scores else 100
        
        return {
            'borders_detected': borders_detected,
            'borders_found': borders_found,
            'avg_uniformity': avg_uniformity,
            'border_info': f'{borders_found}/4 borders detected with avg uniformity {avg_uniformity:.1f}'
        }
        
    except Exception as e:
        logging.error(f"Border detection failed: {e}")
        return {'borders_detected': False, 'border_info': f'Error: {str(e)}'}


def check_canvas_extension(traj, env_info, task_info):
    """
    Main verifier function for canvas extension task.
    Checks:
    1. Canvas dimensions increased by ~200px width and ~150px height
    2. Original content preserved and centered
    3. New canvas areas (borders) detected
    4. Proper positioning maintained
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
        "/home/ga/Desktop/extended_canvas.jpg",
        "/home/ga/Desktop/extended_canvas.png",
        "/home/ga/Desktop/extended_canvas.jpeg",
        "/home/ga/Desktop/canvas_extended.jpg",
        "/home/ga/Desktop/base_image_extended.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/base_image.jpg",
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
        
        # Verify canvas dimensions
        dimension_check = verify_canvas_dimensions(original_image, result_image)
        
        # Verify content preservation
        content_check = verify_content_preservation(original_image, result_image)
        
        # Detect canvas borders
        border_check = detect_canvas_borders(original_image, result_image)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {dimension_check['original_size']}")
        feedback_parts.append(f"Result size: {dimension_check['result_size']}")
        feedback_parts.append(f"Width increase: {dimension_check['width_increase']}px (target: {dimension_check['width_target']}px)")
        feedback_parts.append(f"Height increase: {dimension_check['height_increase']}px (target: {dimension_check['height_target']}px)")
        feedback_parts.append(f"Dimensions correct: {'✅' if dimension_check['dimensions_correct'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_check['content_preserved'] else '❌'} (similarity: {content_check['similarity']:.3f})")
        feedback_parts.append(f"Canvas borders detected: {'✅' if border_check['borders_detected'] else '❌'}")
        feedback_parts.append(f"Border info: {border_check['border_info']}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimension_check['dimensions_correct']:
            criteria_met += 1
        if content_check['content_preserved']:
            criteria_met += 1
        if border_check['borders_detected']:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect canvas extension!")
        elif passed:
            feedback_parts.append("✅ Good canvas extension!")
        else:
            feedback_parts.append("❌ Canvas extension needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in canvas extension verification: {e}")
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
    result = check_canvas_extension([], {}, {})
    print(f"Test result: {result}")