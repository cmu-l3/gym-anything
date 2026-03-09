#!/usr/bin/env python3
"""
Verifier for GIMP paintbrush stroke task.
Checks if a visible brushstroke was added to the image using delta-based analysis.
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


def detect_brushstroke_changes(original_img, result_img):
    """
    Detect brushstroke changes using pixel-wise delta analysis.
    Returns information about changed regions and their characteristics.
    """
    # Ensure images are the same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB for consistent comparison
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    delta = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate magnitude of change for each pixel
    magnitude = np.sqrt(np.sum(delta ** 2, axis=2))
    
    # Identify significantly changed pixels (likely brushstroke)
    significant_threshold = 30  # Minimum intensity change to be considered significant
    changed_pixels = magnitude > significant_threshold
    total_changed = np.sum(changed_pixels)
    
    return {
        'magnitude': magnitude,
        'changed_pixels': changed_pixels,
        'total_changed_pixels': total_changed,
        'change_percentage': (total_changed / (orig_array.shape[0] * orig_array.shape[1])) * 100
    }


def analyze_stroke_connectivity(changed_pixels):
    """
    Analyze connectivity of changed pixels to identify coherent stroke regions.
    Uses connected component analysis if scipy is available, otherwise uses fallback.
    """
    stroke_regions = []
    
    try:
        from scipy.ndimage import label, find_objects
        
        # Find connected components (clusters) of changed pixels
        labeled_regions, num_regions = label(changed_pixels)
        
        for i in range(1, num_regions + 1):
            region_mask = (labeled_regions == i)
            area = np.sum(region_mask)
            
            # Filter out very small regions (likely noise)
            if area >= 100:  # Minimum area for a meaningful stroke segment
                # Get bounding box
                objects = find_objects(labeled_regions == i)
                if objects and objects[0]:
                    y_slice, x_slice = objects[0]
                    
                    stroke_regions.append({
                        'area': area,
                        'bbox': (x_slice.start, y_slice.start, x_slice.stop, y_slice.stop),
                        'width': x_slice.stop - x_slice.start,
                        'height': y_slice.stop - y_slice.start
                    })
        
        # Sort by area (largest regions first)
        stroke_regions.sort(key=lambda x: x['area'], reverse=True)
        
    except ImportError:
        logging.warning("SciPy not available, using fallback connectivity analysis")
        
        # Simple fallback: look for reasonably sized rectangular regions of changes
        height, width = changed_pixels.shape
        
        # Divide into grid and look for regions with high change density
        grid_rows, grid_cols = 8, 12  # Higher resolution grid for stroke detection
        cell_height = height // grid_rows
        cell_width = width // grid_cols
        
        for r in range(grid_rows):
            for c in range(grid_cols):
                y1 = r * cell_height
                y2 = min((r + 1) * cell_height, height)
                x1 = c * cell_width
                x2 = min((c + 1) * cell_width, width)
                
                cell_changes = changed_pixels[y1:y2, x1:x2]
                cell_area = np.sum(cell_changes)
                
                if cell_area > 50:  # Minimum change area in cell
                    stroke_regions.append({
                        'area': cell_area,
                        'bbox': (x1, y1, x2, y2),
                        'width': x2 - x1,
                        'height': y2 - y1
                    })
        
        # Sort by area
        stroke_regions.sort(key=lambda x: x['area'], reverse=True)
    
    return stroke_regions


def analyze_color_contrast(original_img, result_img, changed_pixels):
    """
    Analyze whether the painted stroke provides good contrast with the original image.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Get colors in changed regions
    if np.sum(changed_pixels) == 0:
        return {'has_contrast': False, 'avg_contrast': 0}
    
    # Calculate average colors in changed vs unchanged regions
    changed_colors = result_array[changed_pixels]
    unchanged_colors = orig_array[~changed_pixels]
    
    if len(changed_colors) == 0 or len(unchanged_colors) == 0:
        return {'has_contrast': False, 'avg_contrast': 0}
    
    # Calculate average intensities
    avg_changed_intensity = np.mean(changed_colors)
    avg_background_intensity = np.mean(unchanged_colors)
    
    # Calculate contrast
    contrast = abs(avg_changed_intensity - avg_background_intensity)
    
    return {
        'has_contrast': contrast > 40,  # Minimum contrast threshold
        'avg_contrast': contrast,
        'avg_changed_intensity': avg_changed_intensity,
        'avg_background_intensity': avg_background_intensity
    }


def validate_stroke_shape(stroke_regions):
    """
    Validate that detected regions have stroke-like characteristics.
    """
    if not stroke_regions:
        return {'valid_stroke_shape': False, 'total_stroke_area': 0}
    
    total_area = sum(region['area'] for region in stroke_regions)
    valid_shapes = 0
    
    for region in stroke_regions:
        width = region['width']
        height = region['height']
        area = region['area']
        
        # Check for reasonable stroke dimensions
        # Strokes should be elongated (aspect ratio) or reasonably sized
        aspect_ratio = max(width, height) / max(min(width, height), 1)
        
        # Valid if: elongated stroke OR reasonably sized blob
        if aspect_ratio > 2.0 or (width > 20 and height > 20 and area > 400):
            valid_shapes += 1
    
    return {
        'valid_stroke_shape': valid_shapes > 0,
        'total_stroke_area': total_area,
        'valid_regions': valid_shapes,
        'total_regions': len(stroke_regions)
    }


def check_paintbrush_stroke(traj, env_info, task_info):
    """
    Main verifier function for paintbrush stroke task.
    Checks:
    1. Substantial change (at least 1000 pixels significantly modified)
    2. Connected stroke (coherent regions, not random noise)
    3. Visible contrast (painted color contrasts with background)
    4. Reasonable shape (stroke-like characteristics)
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
        "/home/ga/Desktop/painted_image.jpg",
        "/home/ga/Desktop/painted_image.png",
        "/home/ga/Desktop/painted_image.jpeg",
        "/home/ga/Desktop/photo_canvas_painted.jpg",
        "/home/ga/Desktop/brushstroke.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_canvas.jpg",
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
        
        # Detect brushstroke changes
        change_analysis = detect_brushstroke_changes(original_image, result_image)
        
        # Analyze stroke connectivity
        stroke_regions = analyze_stroke_connectivity(change_analysis['changed_pixels'])
        
        # Analyze color contrast
        contrast_analysis = analyze_color_contrast(original_image, result_image, change_analysis['changed_pixels'])
        
        # Validate stroke shape
        shape_analysis = validate_stroke_shape(stroke_regions)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Pixels changed: {change_analysis['total_changed_pixels']}")
        feedback_parts.append(f"Change percentage: {change_analysis['change_percentage']:.2f}%")
        feedback_parts.append(f"Stroke regions found: {len(stroke_regions)}")
        feedback_parts.append(f"Total stroke area: {shape_analysis['total_stroke_area']}")
        feedback_parts.append(f"Color contrast: {contrast_analysis['avg_contrast']:.1f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Substantial change (at least 1000 pixels)
        substantial_change = change_analysis['total_changed_pixels'] >= 1000
        if substantial_change:
            criteria_met += 1
        feedback_parts.append(f"Substantial change (≥1000px): {'✅' if substantial_change else '❌'}")
        
        # 2. Connected stroke (coherent regions detected)
        connected_stroke = len(stroke_regions) > 0 and shape_analysis['total_stroke_area'] >= 500
        if connected_stroke:
            criteria_met += 1
        feedback_parts.append(f"Connected stroke regions: {'✅' if connected_stroke else '❌'}")
        
        # 3. Visible contrast (good color contrast)
        visible_contrast = contrast_analysis['has_contrast']
        if visible_contrast:
            criteria_met += 1
        feedback_parts.append(f"Visible contrast: {'✅' if visible_contrast else '❌'}")
        
        # 4. Reasonable shape (stroke-like characteristics)
        reasonable_shape = shape_analysis['valid_stroke_shape']
        if reasonable_shape:
            criteria_met += 1
        feedback_parts.append(f"Stroke-like shape: {'✅' if reasonable_shape else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent brushstroke!")
        elif passed:
            feedback_parts.append("✅ Good brushstroke detected!")
        else:
            feedback_parts.append("❌ Brushstroke needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in paintbrush stroke verification: {e}")
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
    result = check_paintbrush_stroke([], {}, {})
    print(f"Test result: {result}")