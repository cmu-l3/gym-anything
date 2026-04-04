#!/usr/bin/env python3
"""
Verifier for GIMP rectangle selection and delete task.
Checks if a rectangular area was successfully deleted (made transparent) in the upper region.
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


def detect_rectangular_deletion(original_img, result_img):
    """
    Detect rectangular transparent areas that indicate successful deletion.
    Uses alpha channel analysis and connected component detection.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert result to RGBA to access alpha channel
    if result_img.mode != 'RGBA':
        result_img = result_img.convert('RGBA')
    
    result_array = np.array(result_img)
    alpha_channel = result_array[:, :, 3]
    
    # Find fully transparent pixels (alpha = 0)
    transparent_pixels = (alpha_channel == 0)
    
    if not np.any(transparent_pixels):
        return {
            'rectangles_found': [],
            'total_transparent_area': 0,
            'has_deletion': False,
            'error': 'No transparent areas detected'
        }
    
    total_transparent_area = np.sum(transparent_pixels)
    
    # Try to find rectangular transparent regions using connected components
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(transparent_pixels)
        objects = find_objects(labeled_regions)
        
        rectangles = []
        for i, obj in enumerate(objects):
            if obj is None:
                continue
                
            y_slice, x_slice = obj
            width = x_slice.stop - x_slice.start
            height = y_slice.stop - y_slice.start
            area = width * height
            
            # Get the actual transparent pixels in this region
            region_mask = (labeled_regions == i + 1)
            region_transparent_area = np.sum(region_mask)
            
            # Check if region is rectangular (most pixels in bounding box are transparent)
            rectangularity = region_transparent_area / area if area > 0 else 0
            
            # Filter for reasonably sized rectangular regions
            if (area >= 2500 and  # Minimum 50x50 pixels
                rectangularity >= 0.80 and  # At least 80% rectangular
                width >= 30 and height >= 30):  # Reasonable dimensions
                
                # Determine position in image
                center_y = (y_slice.start + y_slice.stop) // 2
                center_x = (x_slice.start + x_slice.stop) // 2
                img_height, img_width = result_array.shape[:2]
                
                # Check if in upper portion (top 60% of image)
                is_upper = center_y < img_height * 0.6
                
                rectangles.append({
                    'bbox': (x_slice.start, y_slice.start, x_slice.stop, y_slice.stop),
                    'width': width,
                    'height': height,
                    'area': region_transparent_area,
                    'rectangularity': rectangularity,
                    'center': (center_x, center_y),
                    'is_upper': is_upper,
                    'position': 'upper' if is_upper else 'lower'
                })
        
        # Sort by area (largest first)
        rectangles.sort(key=lambda x: x['area'], reverse=True)
        
        return {
            'rectangles_found': rectangles,
            'total_transparent_area': total_transparent_area,
            'has_deletion': len(rectangles) > 0,
            'error': None
        }
        
    except ImportError:
        # Fallback: Simple grid-based analysis if scipy not available
        logging.warning("SciPy not available, using simple analysis")
        
        # Check for significant transparent areas
        height, width = transparent_pixels.shape
        transparent_ratio = total_transparent_area / (width * height)
        
        # Simple rectangular check: look for contiguous transparent regions
        has_rectangular_deletion = False
        if transparent_ratio > 0.02:  # At least 2% of image is transparent
            # Check if there are solid blocks of transparency (simple heuristic)
            # Look in upper portion for rectangular patterns
            upper_region = transparent_pixels[:int(height * 0.6), :]
            upper_transparent = np.sum(upper_region)
            
            if upper_transparent > 1000:  # Reasonable amount of transparency in upper region
                has_rectangular_deletion = True
        
        return {
            'rectangles_found': [],
            'total_transparent_area': total_transparent_area,
            'has_deletion': has_rectangular_deletion,
            'error': 'SciPy not available - using simple analysis'
        }


def check_content_preservation(original_img, result_img, deletion_info):
    """
    Check that non-deleted areas of the image remain unchanged.
    """
    # Convert to same mode for comparison
    if original_img.mode != result_img.mode:
        if result_img.mode == 'RGBA':
            original_img = original_img.convert('RGBA')
        else:
            result_img = result_img.convert(original_img.mode)
    
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # For images with alpha channel, focus on RGB channels for non-transparent areas
    if result_img.mode == 'RGBA':
        alpha_channel = result_array[:, :, 3]
        non_transparent = alpha_channel > 0
        
        if np.any(non_transparent):
            # Compare RGB values only in non-transparent areas
            orig_rgb = orig_array[:, :, :3] if orig_array.shape[2] >= 3 else orig_array
            result_rgb = result_array[:, :, :3]
            
            # Calculate differences in non-transparent areas
            rgb_diff = np.abs(orig_rgb.astype(np.float32) - result_rgb.astype(np.float32))
            
            # Only check differences in non-transparent areas
            preserved_areas = non_transparent[:, :, np.newaxis] if len(non_transparent.shape) == 2 else non_transparent
            preserved_diff = rgb_diff[preserved_areas.squeeze()]
            
            if len(preserved_diff) > 0:
                mean_preserved_diff = np.mean(preserved_diff)
                content_preserved = mean_preserved_diff < 10  # Allow small differences due to compression
            else:
                content_preserved = True  # No non-transparent areas to compare
        else:
            content_preserved = False  # Everything is transparent
    else:
        # Simple comparison for non-alpha images
        diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
        mean_diff = np.mean(diff)
        content_preserved = mean_diff < 50  # Allow for deletion changes
    
    return content_preserved


def check_rect_deletion(traj, env_info, task_info):
    """
    Main verifier function for rectangle selection and delete task.
    Checks:
    1. Rectangular transparent area was created
    2. Deletion is positioned in upper area of image  
    3. Deleted rectangle is reasonably sized
    4. Non-deleted content is preserved
    5. Image was meaningfully modified
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
        "/home/ga/Desktop/rect_deleted.png",
        "/home/ga/Desktop/rect_deleted.jpg", 
        "/home/ga/Desktop/rect_deleted.jpeg",
        "/home/ga/Desktop/landscape_rect_edited.png",
        "/home/ga/Desktop/landscape_rect_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_rect.jpg",
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
        
        # Detect rectangular deletions
        deletion_info = detect_rectangular_deletion(original_image, result_image)
        
        # Check content preservation  
        content_preserved = check_content_preservation(original_image, result_image, deletion_info)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size or not np.array_equal(
            np.array(original_image.convert('RGB')), 
            np.array(result_image.convert('RGB'))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Total transparent area: {deletion_info['total_transparent_area']} pixels")
        feedback_parts.append(f"Rectangles detected: {len(deletion_info['rectangles_found'])}")
        
        if deletion_info['error']:
            feedback_parts.append(f"Analysis note: {deletion_info['error']}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Rectangular deletion detected
        has_rectangular_deletion = deletion_info['has_deletion']
        if has_rectangular_deletion:
            criteria_met += 1
        feedback_parts.append(f"Rectangular deletion detected: {'✅' if has_rectangular_deletion else '❌'}")
        
        # 2. Deletion in upper area (if we have detailed rectangle info)
        upper_deletion = False
        if deletion_info['rectangles_found']:
            upper_rectangles = [r for r in deletion_info['rectangles_found'] if r['is_upper']]
            upper_deletion = len(upper_rectangles) > 0
            if upper_rectangles:
                best_rect = upper_rectangles[0]
                feedback_parts.append(f"Best rectangle: {best_rect['width']}x{best_rect['height']} at {best_rect['center']}")
        else:
            # For fallback analysis, check if transparency is in upper region
            if result_image.mode == 'RGBA':
                result_array = np.array(result_image)
                height = result_array.shape[0]
                upper_region = result_array[:int(height * 0.6), :, 3]  # Alpha channel of upper region
                upper_transparent = np.sum(upper_region == 0)
                upper_deletion = upper_transparent > 500  # Some transparency in upper region
        
        if upper_deletion:
            criteria_met += 1
        feedback_parts.append(f"Deletion in upper area: {'✅' if upper_deletion else '❌'}")
        
        # 3. Adequate size (minimum 50x50 pixels equivalent)
        adequate_size = deletion_info['total_transparent_area'] >= 2500
        if adequate_size:
            criteria_met += 1
        feedback_parts.append(f"Adequate deletion size (≥2500px): {'✅' if adequate_size else '❌'}")
        
        # 4. Content preserved in non-deleted areas
        if content_preserved:
            criteria_met += 1
        feedback_parts.append(f"Non-deleted content preserved: {'✅' if content_preserved else '❌'}")
        
        # 5. Image was modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # Need at least 3.5/5 criteria (70%)
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect rectangular deletion!")
        elif passed:
            feedback_parts.append("✅ Good rectangular deletion!")
        else:
            feedback_parts.append("❌ Rectangular deletion needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rectangle deletion verification: {e}")
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
    result = check_rect_deletion([], {}, {})
    print(f"Test result: {result}")