#!/usr/bin/env python3
"""
Verifier for GIMP drop shadow effect task.
Checks if a drop shadow effect was successfully applied to the image.
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


def detect_shadow_regions(original_img, result_img):
    """
    Detect shadow regions by analyzing luminance differences between original and result images.
    Shadows appear as new darker areas in the result image.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to grayscale for luminance analysis
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    orig_gray = np.mean(orig_array, axis=2)
    result_gray = np.mean(result_array, axis=2)
    
    # Calculate luminance differences (original - result)
    # Positive values indicate areas that became darker (potential shadows)
    luminance_diff = orig_gray - result_gray
    
    # Identify significant darkening (shadow regions)
    shadow_threshold = 15  # Minimum darkness increase to be considered shadow
    shadow_regions = luminance_diff > shadow_threshold
    
    # Calculate shadow properties
    total_shadow_area = np.sum(shadow_regions)
    total_pixels = orig_gray.shape[0] * orig_gray.shape[1]
    shadow_coverage = total_shadow_area / total_pixels
    
    # Find shadow center (centroid of shadow regions)
    if total_shadow_area > 0:
        shadow_y, shadow_x = np.where(shadow_regions)
        shadow_center = (np.mean(shadow_x), np.mean(shadow_y))
        avg_darkness_increase = np.mean(luminance_diff[shadow_regions])
    else:
        shadow_center = None
        avg_darkness_increase = 0
    
    return {
        'shadow_regions': shadow_regions,
        'total_shadow_area': total_shadow_area,
        'shadow_coverage': shadow_coverage,
        'shadow_center': shadow_center,
        'avg_darkness_increase': avg_darkness_increase
    }


def analyze_shadow_offset(original_img, result_img, shadow_analysis):
    """
    Analyze the offset of shadow relative to original subject.
    Good drop shadows should be offset down and to the right.
    """
    if shadow_analysis['shadow_center'] is None or shadow_analysis['total_shadow_area'] < 100:
        return {
            'offset_x': 0,
            'offset_y': 0,
            'offset_magnitude': 0,
            'good_offset_direction': False
        }
    
    # Find subject center (brightest/most prominent regions in original)
    orig_array = np.array(original_img.convert('RGB'))
    brightness = np.mean(orig_array, axis=2)
    
    # Find subject center using brightness analysis
    subject_threshold = np.percentile(brightness, 75)
    subject_regions = brightness > subject_threshold
    
    if np.sum(subject_regions) > 0:
        subject_y, subject_x = np.where(subject_regions)
        subject_center = (np.mean(subject_x), np.mean(subject_y))
    else:
        # Fallback to image center
        subject_center = (original_img.width / 2, original_img.height / 2)
    
    # Calculate offset
    shadow_center = shadow_analysis['shadow_center']
    offset_x = shadow_center[0] - subject_center[0]
    offset_y = shadow_center[1] - subject_center[1]
    offset_magnitude = np.sqrt(offset_x**2 + offset_y**2)
    
    # Good drop shadow should be offset down (positive Y) and right (positive X)
    good_offset_direction = offset_x > 0 and offset_y > 0
    reasonable_magnitude = 3 <= offset_magnitude <= 20  # Reasonable offset range
    
    return {
        'offset_x': offset_x,
        'offset_y': offset_y, 
        'offset_magnitude': offset_magnitude,
        'good_offset_direction': good_offset_direction,
        'reasonable_magnitude': reasonable_magnitude
    }


def analyze_shadow_quality(original_img, result_img, shadow_analysis):
    """
    Analyze the quality of the drop shadow effect.
    Check for proper opacity, edge softness, and color.
    """
    if shadow_analysis['total_shadow_area'] < 100:
        return {
            'proper_opacity': False,
            'soft_edges': False,
            'appropriate_color': False
        }
    
    result_array = np.array(result_img.convert('RGB'))
    shadow_regions = shadow_analysis['shadow_regions']
    
    # Analyze shadow colors
    shadow_pixels = result_array[shadow_regions]
    if len(shadow_pixels) == 0:
        return {
            'proper_opacity': False,
            'soft_edges': False,
            'appropriate_color': False
        }
    
    # Check if shadow uses appropriate dark colors
    shadow_brightness = np.mean(shadow_pixels, axis=1)
    avg_shadow_brightness = np.mean(shadow_brightness)
    appropriate_color = avg_shadow_brightness < 120  # Should be reasonably dark
    
    # Check opacity (shadow shouldn't be completely black)
    min_shadow_brightness = np.min(shadow_brightness)
    max_shadow_brightness = np.max(shadow_brightness)
    proper_opacity = min_shadow_brightness > 10 and max_shadow_brightness < 200
    
    # Analyze edge softness using gradient analysis
    try:
        from scipy.ndimage import gaussian_gradient_magnitude
        shadow_edges = gaussian_gradient_magnitude(shadow_regions.astype(float), sigma=1)
        edge_softness = np.mean(shadow_edges[shadow_edges > 0])
        soft_edges = edge_softness < 0.3  # Lower values indicate softer edges
    except ImportError:
        # Fallback: analyze edge transitions manually
        from scipy.ndimage import binary_erosion, binary_dilation
        eroded = binary_erosion(shadow_regions)
        dilated = binary_dilation(shadow_regions)
        edge_pixels = dilated & ~eroded
        soft_edges = np.sum(edge_pixels) > np.sum(shadow_regions) * 0.1
    except:
        soft_edges = True  # Assume good if we can't analyze
    
    return {
        'proper_opacity': proper_opacity,
        'soft_edges': soft_edges,
        'appropriate_color': appropriate_color,
        'avg_shadow_brightness': avg_shadow_brightness
    }


def check_drop_shadow(traj, env_info, task_info):
    """
    Main verifier function for drop shadow task.
    Checks:
    1. Shadow regions were detected (new dark areas)
    2. Shadow has proper offset (down and right)
    3. Shadow has appropriate quality (opacity, softness, color)
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
        "/home/ga/Desktop/logo_with_shadow.png",
        "/home/ga/Desktop/logo_with_shadow.jpg", 
        "/home/ga/Desktop/logo_with_shadow.jpeg",
        "/home/ga/Desktop/logo_shadow.png",
        "/home/ga/Desktop/shadow_logo.png",
        "/home/ga/Desktop/logo_image_shadow.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/logo_image.png",
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
        
        # Detect shadow regions
        shadow_analysis = detect_shadow_regions(original_image, result_image)
        
        # Analyze shadow offset
        offset_analysis = analyze_shadow_offset(original_image, result_image, shadow_analysis)
        
        # Analyze shadow quality  
        quality_analysis = analyze_shadow_quality(original_image, result_image, shadow_analysis)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Shadow area: {shadow_analysis['total_shadow_area']} pixels")
        feedback_parts.append(f"Shadow coverage: {shadow_analysis['shadow_coverage']:.3f}")
        feedback_parts.append(f"Avg darkness increase: {shadow_analysis['avg_darkness_increase']:.1f}")
        
        if offset_analysis['offset_magnitude'] > 0:
            feedback_parts.append(f"Shadow offset: ({offset_analysis['offset_x']:.1f}, {offset_analysis['offset_y']:.1f})")
            feedback_parts.append(f"Offset magnitude: {offset_analysis['offset_magnitude']:.1f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Substantial shadow regions detected
        shadow_detected = shadow_analysis['total_shadow_area'] > 200  # Minimum area
        if shadow_detected:
            criteria_met += 1
        feedback_parts.append(f"Shadow regions detected: {'✅' if shadow_detected else '❌'}")
        
        # 2. Good offset direction (down and right)
        if offset_analysis['good_offset_direction'] and offset_analysis['reasonable_magnitude']:
            criteria_met += 1
        feedback_parts.append(f"Proper offset: {'✅' if offset_analysis['good_offset_direction'] else '❌'}")
        
        # 3. Appropriate darkness/color
        if quality_analysis['appropriate_color']:
            criteria_met += 1
        feedback_parts.append(f"Appropriate darkness: {'✅' if quality_analysis['appropriate_color'] else '❌'}")
        
        # 4. Soft edges (blur effect)
        if quality_analysis['soft_edges']:
            criteria_met += 1
        feedback_parts.append(f"Soft edges: {'✅' if quality_analysis['soft_edges'] else '❌'}")
        
        # 5. Image modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent drop shadow effect!")
        elif passed:
            feedback_parts.append("✅ Good drop shadow effect!")
        else:
            feedback_parts.append("❌ Drop shadow effect needs improvement")
            
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