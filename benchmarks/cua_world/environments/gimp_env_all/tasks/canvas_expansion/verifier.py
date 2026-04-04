#!/usr/bin/env python3
"""
Verifier for GIMP canvas expansion task.
Checks if canvas was expanded by ~100px in both dimensions while preserving centered content.
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
    HAS_SSIM = True
except ImportError:
    HAS_SSIM = False
    logging.warning("scikit-image not available, using basic similarity check")


def check_dimension_increase(original_size, result_size, expected_increase=100, tolerance=10):
    """Check if dimensions increased by expected amount within tolerance."""
    orig_width, orig_height = original_size
    result_width, result_height = result_size
    
    width_increase = result_width - orig_width
    height_increase = result_height - orig_height
    
    width_ok = abs(width_increase - expected_increase) <= tolerance
    height_ok = abs(height_increase - expected_increase) <= tolerance
    
    return {
        'width_ok': width_ok,
        'height_ok': height_ok,
        'width_increase': width_increase,
        'height_increase': height_increase,
        'dimensions_increased': width_increase > 50 and height_increase > 50  # At least 50px increase
    }


def extract_centered_region(result_img, original_size):
    """Extract the center region from result image that should match the original."""
    result_width, result_height = result_img.size
    orig_width, orig_height = original_size
    
    # Calculate where the original image should be positioned (centered)
    x_offset = (result_width - orig_width) // 2
    y_offset = (result_height - orig_height) // 2
    
    # Ensure offsets are non-negative
    x_offset = max(0, x_offset)
    y_offset = max(0, y_offset)
    
    # Extract the region
    extracted = result_img.crop((
        x_offset, y_offset,
        x_offset + orig_width, y_offset + orig_height
    ))
    
    return extracted, (x_offset, y_offset)


def check_content_preservation(original_img, result_img, similarity_threshold=0.95):
    """Check if original content is preserved in the center of the expanded canvas."""
    # Extract center region from result that should match original
    extracted_center, offset = extract_centered_region(result_img, original_img.size)
    
    # Ensure both images are same mode for comparison
    if original_img.mode != extracted_center.mode:
        extracted_center = extracted_center.convert(original_img.mode)
    
    # Calculate similarity
    if HAS_SSIM and original_img.size == extracted_center.size:
        try:
            # Convert to RGB for SSIM calculation
            orig_rgb = np.array(original_img.convert('RGB'))
            extract_rgb = np.array(extracted_center.convert('RGB'))
            
            # Calculate SSIM
            similarity = ssim(orig_rgb, extract_rgb, multichannel=True, channel_axis=2)
            content_preserved = similarity >= similarity_threshold
            
            return {
                'content_preserved': content_preserved,
                'similarity_score': similarity,
                'method': 'SSIM',
                'offset': offset
            }
        except Exception as e:
            logging.warning(f"SSIM calculation failed: {e}, falling back to simple comparison")
    
    # Fallback: simple pixel-wise comparison
    if original_img.size != extracted_center.size:
        return {
            'content_preserved': False,
            'similarity_score': 0.0,
            'method': 'size_mismatch',
            'offset': offset
        }
    
    # Calculate pixel-wise difference
    orig_array = np.array(original_img.convert('RGB'))
    extract_array = np.array(extracted_center.convert('RGB'))
    
    # Calculate mean absolute difference
    diff = np.mean(np.abs(orig_array.astype(np.float32) - extract_array.astype(np.float32)))
    max_diff = 255.0 * 3  # Maximum possible difference for RGB
    similarity = 1.0 - (diff / max_diff)
    
    content_preserved = similarity >= similarity_threshold
    
    return {
        'content_preserved': content_preserved,
        'similarity_score': similarity,
        'method': 'pixel_diff',
        'offset': offset
    }


def check_centering(result_img, original_size):
    """Check if the original content is properly centered in the expanded canvas."""
    result_width, result_height = result_img.size
    orig_width, orig_height = original_size
    
    # Calculate expected centering offsets
    expected_x_offset = (result_width - orig_width) // 2
    expected_y_offset = (result_height - orig_height) // 2
    
    # Extract actual center region
    _, actual_offset = extract_centered_region(result_img, original_size)
    actual_x_offset, actual_y_offset = actual_offset
    
    # Check if offsets are close to expected (within 5 pixels tolerance)
    x_centered = abs(actual_x_offset - expected_x_offset) <= 5
    y_centered = abs(actual_y_offset - expected_y_offset) <= 5
    
    return {
        'properly_centered': x_centered and y_centered,
        'expected_offset': (expected_x_offset, expected_y_offset),
        'actual_offset': actual_offset,
        'x_centered': x_centered,
        'y_centered': y_centered
    }


def detect_added_space(result_img, original_size):
    """Detect if space was actually added around the original image."""
    result_width, result_height = result_img.size
    orig_width, orig_height = original_size
    
    # Check if result is larger than original
    space_added = result_width > orig_width and result_height > orig_height
    
    if not space_added:
        return {
            'space_detected': False,
            'border_analysis': None
        }
    
    # Analyze border regions to confirm they contain new content
    result_array = np.array(result_img.convert('RGB'))
    
    # Sample border regions
    top_border = result_array[:10, :, :]  # Top 10 pixels
    bottom_border = result_array[-10:, :, :]  # Bottom 10 pixels
    left_border = result_array[:, :10, :]  # Left 10 pixels
    right_border = result_array[:, -10:, :]  # Right 10 pixels
    
    # Check if borders have consistent color (indicating added space)
    borders_exist = (top_border.size > 0 and bottom_border.size > 0 and 
                    left_border.size > 0 and right_border.size > 0)
    
    return {
        'space_detected': borders_exist,
        'border_analysis': {
            'top_border_size': top_border.shape if top_border.size > 0 else None,
            'result_larger': space_added
        }
    }


def check_canvas_expansion(traj, env_info, task_info):
    """
    Main verifier function for canvas expansion task.
    Checks:
    1. Canvas dimensions increased by ~100px in both directions
    2. Original content is preserved and centered
    3. Added space is detected around the original content
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
        "/home/ga/Desktop/sample_image_expanded.jpg",
        "/home/ga/Desktop/canvas_expanded.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/sample_image.jpg",
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
        
        # Check dimension increases
        dimension_check = check_dimension_increase(original_image.size, result_image.size)
        
        # Check content preservation
        content_check = check_content_preservation(original_image, result_image)
        
        # Check proper centering
        centering_check = check_centering(result_image, original_image.size)
        
        # Check for added space
        space_check = detect_added_space(result_image, original_image.size)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Width increase: {dimension_check['width_increase']}px")
        feedback_parts.append(f"Height increase: {dimension_check['height_increase']}px")
        feedback_parts.append(f"Dimensions increased correctly: {'✅' if dimension_check['dimensions_increased'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_check['content_preserved'] else '❌'}")
        feedback_parts.append(f"Content similarity: {content_check['similarity_score']:.3f}")
        feedback_parts.append(f"Properly centered: {'✅' if centering_check['properly_centered'] else '❌'}")
        feedback_parts.append(f"Added space detected: {'✅' if space_check['space_detected'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimension_check['dimensions_increased']:
            criteria_met += 1
        if content_check['content_preserved']:
            criteria_met += 1
        if centering_check['properly_centered']:
            criteria_met += 1
        if space_check['space_detected']:
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