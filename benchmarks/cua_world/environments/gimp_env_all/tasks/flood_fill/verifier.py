#!/usr/bin/env python3
"""
Verifier for GIMP flood fill task.
Checks if a region was successfully filled with a new color using bucket fill.
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


def analyze_color_changes(original_img, result_img):
    """
    Analyze color changes between original and result images.
    Detect new colors and measure the extent of changes.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise differences
    pixel_diff = np.sum(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)), axis=2)
    
    # Find significantly changed pixels (threshold of 30 intensity units)
    changed_pixels = pixel_diff > 30
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    changed_percentage = np.sum(changed_pixels) / total_pixels * 100
    
    # Analyze color distributions
    orig_colors = orig_array.reshape(-1, 3)
    result_colors = result_array.reshape(-1, 3)
    
    # Find unique colors (with some tolerance for minor variations)
    def get_dominant_colors(colors, min_count=100):
        """Get colors that appear in at least min_count pixels."""
        unique_colors = {}
        for color in colors:
            color_key = tuple((color // 10) * 10)  # Group similar colors
            if color_key in unique_colors:
                unique_colors[color_key] += 1
            else:
                unique_colors[color_key] = 1
        
        return {k: v for k, v in unique_colors.items() if v >= min_count}
    
    orig_dominant = get_dominant_colors(orig_colors)
    result_dominant = get_dominant_colors(result_colors)
    
    # Find new prominent colors
    new_colors = set(result_dominant.keys()) - set(orig_dominant.keys())
    
    return {
        'changed_percentage': changed_percentage,
        'changed_pixels': np.sum(changed_pixels),
        'new_colors': new_colors,
        'new_color_count': len(new_colors),
        'orig_dominant_colors': len(orig_dominant),
        'result_dominant_colors': len(result_dominant)
    }


def detect_filled_regions(original_img, result_img):
    """
    Detect regions that were filled using connected component analysis.
    """
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel differences
    diff = np.sum(np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32)), axis=2)
    
    # Create mask for significantly changed pixels
    changed_mask = diff > 30
    
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(changed_mask)
        
        filled_regions = []
        for i in range(1, num_regions + 1):
            # Get region properties
            region_mask = (labeled_regions == i)
            region_area = np.sum(region_mask)
            
            # Filter out small changes (noise) - look for substantial fills
            if region_area >= 500:  # At least 500 pixels for a meaningful fill
                # Get bounding box
                slices = find_objects(labeled_regions == i)[0]
                if slices is not None:
                    y_slice, x_slice = slices
                    bbox = (x_slice.start, y_slice.start, x_slice.stop, y_slice.stop)
                    
                    # Calculate region properties
                    width = x_slice.stop - x_slice.start
                    height = y_slice.stop - y_slice.start
                    
                    # Get average colors in this region
                    orig_region = orig_array[region_mask]
                    result_region = result_array[region_mask]
                    
                    avg_orig_color = np.mean(orig_region, axis=0)
                    avg_result_color = np.mean(result_region, axis=0)
                    
                    filled_regions.append({
                        'area': region_area,
                        'bbox': bbox,
                        'width': width,
                        'height': height,
                        'center': ((x_slice.start + x_slice.stop) // 2, 
                                 (y_slice.start + y_slice.stop) // 2),
                        'avg_orig_color': avg_orig_color,
                        'avg_result_color': avg_result_color,
                        'compactness': region_area / (width * height)  # How compact/filled the region is
                    })
        
        # Sort by area (largest fills first)
        filled_regions.sort(key=lambda x: x['area'], reverse=True)
        return filled_regions
        
    except ImportError:
        # Fallback without scipy
        logging.warning("scipy not available, using basic change detection")
        changed_area = np.sum(changed_mask)
        if changed_area >= 500:
            return [{'area': changed_area, 'basic_detection': True}]
        return []


def validate_flood_fill_characteristics(filled_regions):
    """
    Validate that the detected regions have characteristics consistent with flood fill.
    """
    characteristics = {
        'has_substantial_fill': False,
        'good_boundary_respect': False,
        'reasonable_shape': False,
        'single_major_fill': False
    }
    
    if not filled_regions:
        return characteristics
    
    largest_region = filled_regions[0]
    
    # Check for substantial fill (at least 500 pixels)
    if largest_region['area'] >= 500:
        characteristics['has_substantial_fill'] = True
    
    # Check shape characteristics (flood fills typically have good compactness)
    if 'compactness' in largest_region and largest_region['compactness'] >= 0.3:
        characteristics['reasonable_shape'] = True
    
    # Check if there's one dominant fill vs many small scattered changes
    if len(filled_regions) <= 3:  # Not too many separate regions
        characteristics['single_major_fill'] = True
    
    # Boundary respect: check if the fill has reasonable aspect ratio
    if ('width' in largest_region and 'height' in largest_region and 
        largest_region['width'] > 20 and largest_region['height'] > 20):
        aspect_ratio = max(largest_region['width'], largest_region['height']) / min(largest_region['width'], largest_region['height'])
        if aspect_ratio <= 3:  # Not extremely elongated
            characteristics['good_boundary_respect'] = True
    
    return characteristics


def check_flood_fill(traj, env_info, task_info):
    """
    Main verifier function for flood fill task.
    Checks:
    1. Significant new color was introduced
    2. Color change is localized to specific regions (not scattered)
    3. Fill characteristics are consistent with bucket fill tool
    4. Adequate coverage and boundary respect
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
        "/home/ga/Desktop/flood_filled_shape.png",
        "/home/ga/Desktop/flood_filled_shape.jpg",
        "/home/ga/Desktop/flood_filled_shape.jpeg",
        "/home/ga/Desktop/geometric_shapes_filled.png",
        "/home/ga/Desktop/filled_shape.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/geometric_shapes.png",
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
        
        # Analyze color changes
        color_analysis = analyze_color_changes(original_image, result_image)
        
        # Detect filled regions
        filled_regions = detect_filled_regions(original_image, result_image)
        
        # Validate flood fill characteristics
        fill_characteristics = validate_flood_fill_characteristics(filled_regions)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Changed pixels: {color_analysis['changed_percentage']:.1f}%")
        feedback_parts.append(f"New colors detected: {color_analysis['new_color_count']}")
        feedback_parts.append(f"Filled regions found: {len(filled_regions)}")
        
        if filled_regions:
            largest_fill = filled_regions[0]
            feedback_parts.append(f"Largest fill area: {largest_fill['area']} pixels")
            if 'center' in largest_fill:
                feedback_parts.append(f"Fill center: {largest_fill['center']}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant new color present (at least 2% of pixels changed)
        significant_change = color_analysis['changed_percentage'] >= 2.0
        if significant_change:
            criteria_met += 1
        feedback_parts.append(f"Significant color change: {'✅' if significant_change else '❌'}")
        
        # 2. Substantial fill area (good-sized region filled)
        if fill_characteristics['has_substantial_fill']:
            criteria_met += 1
        feedback_parts.append(f"Substantial fill detected: {'✅' if fill_characteristics['has_substantial_fill'] else '❌'}")
        
        # 3. Reasonable fill shape and boundary respect
        if fill_characteristics['good_boundary_respect']:
            criteria_met += 1
        feedback_parts.append(f"Good boundary respect: {'✅' if fill_characteristics['good_boundary_respect'] else '❌'}")
        
        # 4. Localized fill (not too scattered)
        if fill_characteristics['single_major_fill']:
            criteria_met += 1
        feedback_parts.append(f"Localized fill: {'✅' if fill_characteristics['single_major_fill'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent flood fill!")
        elif passed:
            feedback_parts.append("✅ Good flood fill operation!")
        else:
            feedback_parts.append("❌ Flood fill needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in flood fill verification: {e}")
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
    result = check_flood_fill([], {}, {})
    print(f"Test result: {result}")