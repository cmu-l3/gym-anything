#!/usr/bin/env python3
"""
Verifier for GIMP rounded corners task.
Checks if rectangular image was given rounded corners with transparent corners.
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


def analyze_corner_transparency(img, corner_size=50):
    """
    Analyze transparency in the four corners of an image.
    Returns statistics about transparency patterns in each corner.
    """
    if img.mode != 'RGBA':
        # If no alpha channel, assume fully opaque
        img = img.convert('RGBA')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    
    # Ensure corner size doesn't exceed image dimensions
    actual_corner_size = min(corner_size, width // 4, height // 4)
    
    # Define corner regions
    corners = {
        'top_left': img_array[0:actual_corner_size, 0:actual_corner_size],
        'top_right': img_array[0:actual_corner_size, width-actual_corner_size:width],
        'bottom_left': img_array[height-actual_corner_size:height, 0:actual_corner_size],
        'bottom_right': img_array[height-actual_corner_size:height, width-actual_corner_size:width]
    }
    
    corner_stats = {}
    
    for corner_name, corner_region in corners.items():
        if corner_region.size == 0:
            continue
            
        alpha_channel = corner_region[:, :, 3]  # Alpha channel
        
        # Calculate transparency metrics
        total_pixels = alpha_channel.size
        transparent_pixels = np.sum(alpha_channel < 250)  # Nearly or fully transparent
        semi_transparent_pixels = np.sum((alpha_channel >= 50) & (alpha_channel < 250))
        opaque_pixels = np.sum(alpha_channel >= 250)
        
        transparency_ratio = transparent_pixels / total_pixels if total_pixels > 0 else 0
        semi_transparency_ratio = semi_transparent_pixels / total_pixels if total_pixels > 0 else 0
        
        corner_stats[corner_name] = {
            'transparency_ratio': transparency_ratio,
            'semi_transparency_ratio': semi_transparency_ratio,
            'avg_alpha': np.mean(alpha_channel),
            'min_alpha': np.min(alpha_channel),
            'total_pixels': total_pixels,
            'transparent_pixels': transparent_pixels
        }
    
    return corner_stats


def detect_curved_corners(img, corner_size=50):
    """
    Detect if corners follow curved patterns rather than straight edges.
    Returns True if transparency patterns suggest curved corners.
    """
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    alpha_channel = img_array[:, :, 3]
    
    # Check corners for curved vs. straight edge patterns
    actual_corner_size = min(corner_size, width // 4, height // 4)
    curved_evidence = []
    
    # Analyze each corner for curved patterns
    corner_regions = [
        (0, actual_corner_size, 0, actual_corner_size),  # top-left
        (0, actual_corner_size, width-actual_corner_size, width),  # top-right
        (height-actual_corner_size, height, 0, actual_corner_size),  # bottom-left
        (height-actual_corner_size, height, width-actual_corner_size, width)  # bottom-right
    ]
    
    for y1, y2, x1, x2 in corner_regions:
        corner_alpha = alpha_channel[y1:y2, x1:x2]
        
        if corner_alpha.size == 0:
            continue
        
        # For curved corners, transparency should gradually increase toward actual corners
        # Check diagonal patterns from center toward corner
        corner_height, corner_width = corner_alpha.shape
        
        if corner_height > 10 and corner_width > 10:
            # Sample transparency along diagonal toward corner
            diagonal_samples = []
            steps = min(10, corner_height // 2, corner_width // 2)
            
            for i in range(steps):
                # Sample from center toward corner
                if y1 == 0 and x1 == 0:  # top-left
                    y_idx = steps - 1 - i
                    x_idx = steps - 1 - i
                elif y1 == 0 and x2 == width:  # top-right
                    y_idx = steps - 1 - i
                    x_idx = corner_width - 1 - (steps - 1 - i)
                elif y2 == height and x1 == 0:  # bottom-left
                    y_idx = corner_height - 1 - (steps - 1 - i)
                    x_idx = steps - 1 - i
                else:  # bottom-right
                    y_idx = corner_height - 1 - (steps - 1 - i)
                    x_idx = corner_width - 1 - (steps - 1 - i)
                
                if 0 <= y_idx < corner_height and 0 <= x_idx < corner_width:
                    diagonal_samples.append(corner_alpha[y_idx, x_idx])
            
            # For rounded corners, transparency should increase toward corner
            if len(diagonal_samples) > 3:
                # Check if there's a general trend toward more transparency
                first_third = np.mean(diagonal_samples[:len(diagonal_samples)//3])
                last_third = np.mean(diagonal_samples[-len(diagonal_samples)//3:])
                
                # Curved corner evidence: later samples more transparent than earlier ones
                if first_third > last_third + 50:  # Significant transparency increase
                    curved_evidence.append(True)
                else:
                    curved_evidence.append(False)
    
    # Return True if majority of corners show curved evidence
    return sum(curved_evidence) >= len(curved_evidence) // 2


def check_center_preservation(original_img, result_img):
    """
    Check if the center region of the image is preserved (not made transparent).
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if result_img.mode != 'RGBA':
        result_img = result_img.convert('RGBA')
    
    result_array = np.array(result_img)
    height, width = result_array.shape[:2]
    
    # Define center region (middle 60% of image)
    center_y1, center_y2 = int(height * 0.2), int(height * 0.8)
    center_x1, center_x2 = int(width * 0.2), int(width * 0.8)
    
    center_region = result_array[center_y1:center_y2, center_x1:center_x2]
    
    if center_region.size == 0:
        return False, 0
    
    center_alpha = center_region[:, :, 3]
    opaque_pixels = np.sum(center_alpha >= 250)  # Fully opaque pixels
    total_pixels = center_alpha.size
    
    preservation_ratio = opaque_pixels / total_pixels if total_pixels > 0 else 0
    preserved = preservation_ratio > 0.95  # At least 95% of center should be opaque
    
    return preserved, preservation_ratio


def estimate_corner_radius(corner_stats, img_size):
    """
    Estimate the corner radius based on transparency patterns.
    """
    width, height = img_size
    min_dim = min(width, height)
    
    # Use average transparency ratio across corners as radius indicator
    avg_transparency = np.mean([stats['transparency_ratio'] for stats in corner_stats.values()])
    
    # Rough estimation: higher transparency ratio suggests larger radius
    # This is a heuristic - exact radius calculation would be more complex
    estimated_radius = avg_transparency * min_dim * 0.3
    
    return estimated_radius


def check_rounded_corners(traj, env_info, task_info):
    """
    Main verifier function for rounded corners task.
    Checks:
    1. Corners show significant transparency (rounded effect applied)
    2. Transparency follows curved patterns, not straight edges
    3. Center content is preserved (not made transparent)
    4. Corner rounding is consistent across all corners
    5. Corner radius is reasonable (not too subtle, not too extreme)
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
        "/home/ga/Desktop/rounded_corners.png",
        "/home/ga/Desktop/rounded_corners.jpg",  # In case exported as JPEG
        "/home/ga/Desktop/rectangle_image_rounded.png",
        "/home/ga/Desktop/corners_rounded.png",
        "/home/ga/Desktop/rectangle_image.png"  # In case exported with original name
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/rectangle_image.jpg",
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
        
        # Analyze corner transparency
        corner_stats = analyze_corner_transparency(result_image)
        
        # Check for curved corner patterns
        has_curved_corners = detect_curved_corners(result_image)
        
        # Check center preservation
        center_preserved, preservation_ratio = check_center_preservation(original_image, result_image)
        
        # Estimate corner radius
        estimated_radius = estimate_corner_radius(corner_stats, result_image.size)
        
        # Check consistency across corners
        transparency_ratios = [stats['transparency_ratio'] for stats in corner_stats.values()]
        avg_transparency = np.mean(transparency_ratios)
        transparency_std = np.std(transparency_ratios)
        consistency_coefficient = transparency_std / (avg_transparency + 1e-6)
        consistent_rounding = consistency_coefficient < 0.3  # Low variation across corners
        
        # Check if image was modified (has transparency where original didn't)
        original_has_alpha = original_image.mode in ['RGBA', 'LA']
        result_has_alpha = result_image.mode in ['RGBA', 'LA']
        image_modified = result_has_alpha or avg_transparency > 0.05
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Original has transparency: {'Yes' if original_has_alpha else 'No'}")
        feedback_parts.append(f"Result has transparency: {'Yes' if result_has_alpha else 'No'}")
        feedback_parts.append(f"Avg corner transparency: {avg_transparency:.2f}")
        feedback_parts.append(f"Estimated radius: {estimated_radius:.1f}px")
        feedback_parts.append(f"Center preserved: {'✅' if center_preserved else '❌'} ({preservation_ratio:.1%})")
        feedback_parts.append(f"Curved corners: {'✅' if has_curved_corners else '❌'}")
        feedback_parts.append(f"Consistent rounding: {'✅' if consistent_rounding else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if image_modified else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Corner transparency present (significant rounding applied)
        corners_transparent = avg_transparency > 0.1
        if corners_transparent:
            criteria_met += 1
        feedback_parts.append(f"Corners transparent: {'✅' if corners_transparent else '❌'}")
        
        # 2. Curved pattern (not just straight cuts)
        if has_curved_corners:
            criteria_met += 1
        
        # 3. Center preserved
        if center_preserved:
            criteria_met += 1
        
        # 4. Consistent rounding across corners
        if consistent_rounding:
            criteria_met += 1
        
        # 5. Appropriate radius (not too extreme)
        appropriate_radius = 5 <= estimated_radius <= min(result_image.size) * 0.3
        if appropriate_radius:
            criteria_met += 1
        feedback_parts.append(f"Appropriate radius: {'✅' if appropriate_radius else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rounded corners!")
        elif passed:
            feedback_parts.append("✅ Good rounded corners!")
        else:
            feedback_parts.append("❌ Rounded corners need improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rounded corners verification: {e}")
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
    result = check_rounded_corners([], {}, {})
    print(f"Test result: {result}")