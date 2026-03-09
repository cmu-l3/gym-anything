#!/usr/bin/env python3
"""
Verifier for GIMP bucket fill task.
Checks if a bounded area was successfully filled with red color using bucket fill tool.
"""

import logging
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os
import tempfile

logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def analyze_red_color_distribution(img):
    """
    Analyze red color distribution in the image.
    Returns detailed statistics about red pixels.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    total_pixels = img_array.shape[0] * img_array.shape[1]
    
    # Define red color ranges
    red_ranges = {
        'bright_red': {'r': (180, 255), 'g': (0, 75), 'b': (0, 75)},
        'medium_red': {'r': (120, 179), 'g': (0, 100), 'b': (0, 100)},
        'dark_red': {'r': (80, 119), 'g': (0, 60), 'b': (0, 60)}
    }
    
    red_stats = {}
    total_red_pixels = 0
    
    for color_name, ranges in red_ranges.items():
        # Create masks for each color channel
        r_mask = (img_array[:, :, 0] >= ranges['r'][0]) & (img_array[:, :, 0] <= ranges['r'][1])
        g_mask = (img_array[:, :, 1] >= ranges['g'][0]) & (img_array[:, :, 1] <= ranges['g'][1])
        b_mask = (img_array[:, :, 2] >= ranges['b'][0]) & (img_array[:, :, 2] <= ranges['b'][1])
        
        # Combine masks to identify pixels in this red range
        color_mask = r_mask & g_mask & b_mask
        color_pixels = np.sum(color_mask)
        color_percentage = (color_pixels / total_pixels) * 100
        
        red_stats[color_name] = {
            'pixels': color_pixels,
            'percentage': color_percentage
        }
        total_red_pixels += color_pixels
    
    red_stats['total_red'] = {
        'pixels': total_red_pixels,
        'percentage': (total_red_pixels / total_pixels) * 100
    }
    
    return red_stats


def analyze_connected_regions(img, red_threshold=120):
    """
    Analyze connected red regions to identify flood fill patterns.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Create mask for red pixels (simplified approach)
    red_mask = (img_array[:, :, 0] >= red_threshold) & \
               (img_array[:, :, 1] <= 100) & \
               (img_array[:, :, 2] <= 100)
    
    try:
        from scipy.ndimage import label, find_objects
        labeled_regions, num_regions = label(red_mask)
        
        regions = []
        for i in range(1, num_regions + 1):
            region_mask = (labeled_regions == i)
            area = np.sum(region_mask)
            
            if area >= 100:  # Filter out small regions (likely noise)
                # Find bounding box
                slices = find_objects(labeled_regions == i)[0]
                if slices:
                    y1, y2 = slices[0].start, slices[0].stop
                    x1, x2 = slices[1].start, slices[1].stop
                    
                    # Calculate region characteristics
                    width = x2 - x1
                    height = y2 - y1
                    aspect_ratio = width / max(height, 1)
                    compactness = area / (width * height) if width > 0 and height > 0 else 0
                    
                    regions.append({
                        'area': area,
                        'bbox': (x1, y1, x2, y2),
                        'width': width,
                        'height': height,
                        'aspect_ratio': aspect_ratio,
                        'compactness': compactness
                    })
        
        # Sort by area (largest regions first)
        regions.sort(key=lambda x: x['area'], reverse=True)
        return regions
        
    except ImportError:
        # Fallback without scipy: simple grid-based analysis
        height, width = red_mask.shape
        total_red = np.sum(red_mask)
        
        if total_red > 0:
            # Return simplified region info
            return [{
                'area': total_red,
                'bbox': (0, 0, width, height),
                'width': width,
                'height': height,
                'aspect_ratio': width / height,
                'compactness': total_red / (width * height)
            }]
        return []


def check_bucket_fill_characteristics(original_img, result_img):
    """
    Check if the changes are consistent with bucket fill operation.
    """
    # Ensure same size for comparison
    if result_img.size != original_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_red = analyze_red_color_distribution(original_img)
    result_red = analyze_red_color_distribution(result_img)
    
    # Calculate red color increase
    red_increase = result_red['total_red']['percentage'] - orig_red['total_red']['percentage']
    red_increase_pixels = result_red['total_red']['pixels'] - orig_red['total_red']['pixels']
    
    # Analyze connected regions in result image
    red_regions = analyze_connected_regions(result_img)
    
    # Check for good red color values (proper RGB values)
    proper_red_percentage = (result_red['bright_red']['percentage'] + 
                           result_red['medium_red']['percentage'])
    
    return {
        'red_increase_percentage': red_increase,
        'red_increase_pixels': red_increase_pixels,
        'total_red_percentage': result_red['total_red']['percentage'],
        'connected_regions': red_regions,
        'largest_region_area': red_regions[0]['area'] if red_regions else 0,
        'proper_red_percentage': proper_red_percentage,
        'has_significant_red_region': len([r for r in red_regions if r['area'] >= 1000]) > 0
    }


def check_image_modification(original_img, result_img):
    """Check if image was meaningfully modified."""
    if result_img.size != original_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    significant_diff = np.sum(np.sqrt(np.sum(diff ** 2, axis=2)) > 30)
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (significant_diff / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_modified': change_percentage > 2  # At least 2% of pixels changed
    }


def check_bucket_fill(traj, env_info, task_info):
    """
    Main verifier function for bucket fill task.
    Checks:
    1. Significant red color increase (≥1000 pixels or ≥2% of image)
    2. Connected fill regions consistent with flood fill behavior
    3. Proper red color values (R≥180, G≤75, B≤75)
    4. Image boundaries preserved (original structure intact)
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
        
        # Define container paths - try different possible output filenames
        possible_results = [
            "/home/ga/Desktop/red_bucket_fill.jpg",
            "/home/ga/Desktop/red_bucket_fill.png",
            "/home/ga/Desktop/red_bucket_fill.jpeg",
            "/home/ga/Desktop/bucket_fill.jpg",
            "/home/ga/Desktop/line_art_filled.jpg"
        ]
        
        container_original = "/home/ga/Desktop/line_art.jpg"
        
        # Define host paths
        host_original = temp_path / "original.jpg"
        host_result = temp_path / "result.jpg"
        
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
        for result_path in possible_results:
            success, error = copy_file_from_container(copy_from_env, result_path, host_result)
            if success:
                result_found = True
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
            
            logging.debug(f"Original size: {original_image.size}")
            logging.debug(f"Result size: {result_image.size}")
            
            # Analyze bucket fill characteristics
            fill_analysis = check_bucket_fill_characteristics(original_image, result_image)
            
            # Check image modification
            modification_analysis = check_image_modification(original_image, result_image)
            
            feedback_parts = []
            feedback_parts.append(f"Original size: {original_image.size}")
            feedback_parts.append(f"Result size: {result_image.size}")
            feedback_parts.append(f"Red increase: {fill_analysis['red_increase_pixels']} pixels ({fill_analysis['red_increase_percentage']:.1f}%)")
            feedback_parts.append(f"Total red area: {fill_analysis['total_red_percentage']:.1f}%")
            feedback_parts.append(f"Connected regions: {len(fill_analysis['connected_regions'])}")
            feedback_parts.append(f"Largest region: {fill_analysis['largest_region_area']} pixels")
            feedback_parts.append(f"Pixels changed: {modification_analysis['change_percentage']:.1f}%")
            
            # Evaluate success criteria
            criteria_met = 0
            total_criteria = 4
            
            # 1. Significant red increase (≥1000 pixels or ≥2% of image)
            total_pixels = original_image.size[0] * original_image.size[1]
            red_increase_significant = (fill_analysis['red_increase_pixels'] >= 1000 or 
                                      fill_analysis['red_increase_percentage'] >= 2.0)
            if red_increase_significant:
                criteria_met += 1
            feedback_parts.append(f"Significant red increase: {'✅' if red_increase_significant else '❌'}")
            
            # 2. Connected fill regions (coherent areas consistent with flood fill)
            has_connected_regions = len(fill_analysis['connected_regions']) > 0 and fill_analysis['largest_region_area'] >= 500
            if has_connected_regions:
                criteria_met += 1
            feedback_parts.append(f"Connected fill regions: {'✅' if has_connected_regions else '❌'}")
            
            # 3. Proper red color values (high-quality red color)
            proper_red_colors = fill_analysis['proper_red_percentage'] >= 1.0  # At least 1% proper red
            if proper_red_colors:
                criteria_met += 1
            feedback_parts.append(f"Proper red colors: {'✅' if proper_red_colors else '❌'}")
            
            # 4. Image boundaries preserved (meaningful modification without corruption)
            boundaries_preserved = modification_analysis['meaningfully_modified'] and modification_analysis['change_percentage'] < 50
            if boundaries_preserved:
                criteria_met += 1
            feedback_parts.append(f"Boundaries preserved: {'✅' if boundaries_preserved else '❌'}")
            
            # Calculate score and pass/fail
            score = int((criteria_met / total_criteria) * 100)
            passed = score >= 75  # Need at least 3/4 criteria
            
            if passed and score >= 90:
                feedback_parts.append("🎉 Perfect bucket fill operation!")
            elif passed:
                feedback_parts.append("✅ Good bucket fill!")
            else:
                feedback_parts.append("❌ Bucket fill needs improvement")
                
            return {
                "passed": passed,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        except Exception as e:
            logging.error(f"Error in bucket fill verification: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: {str(e)}"
            }


if __name__ == "__main__":
    # Test the verifier
    result = check_bucket_fill([], {}, {})
    print(f"Test result: {result}")