"""
Verifier for text overlay task.
Checks that text "SUMMER VIBES" was added to the image with proper styling.
"""

import os
import sys
import tempfile
import logging
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np

# Set up logging
logging.basicConfig(level=logging.DEBUG)

try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False
    logging.warning("OpenCV not available, using basic text detection")


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def detect_text_regions_by_delta(original_img, result_img):
    """
    Detect text regions by analyzing the difference between original and result images.
    Uses clustering on high-delta pixels to identify text areas.
    """
    # Ensure images are the same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    # Convert to numpy arrays
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate pixel-wise difference (delta)
    delta = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate magnitude of change for each pixel
    delta_magnitude = np.sqrt(np.sum(delta ** 2, axis=2))
    
    # Threshold to find significantly changed pixels (likely text)
    change_threshold = np.percentile(delta_magnitude, 95)  # Top 5% of changes
    changed_pixels = delta_magnitude > max(change_threshold, 30)  # At least 30 intensity units
    
    # Find connected components (clusters) of changed pixels
    try:
        from scipy.ndimage import label, find_objects
        labeled_array, num_features = label(changed_pixels)
        text_regions = []
        
        for i in range(1, num_features + 1):
            # Get bounding box of this cluster
            slices = find_objects(labeled_array == i)[0]
            if slices is None:
                continue
                
            y1, y2 = slices[0].start, slices[0].stop
            x1, x2 = slices[1].start, slices[1].stop
            
            # Filter out very small regions (noise)
            width = x2 - x1
            height = y2 - y1
            area = np.sum(labeled_array == i)
            
            if width > 20 and height > 8 and area > 100:  # Reasonable text dimensions
                # Calculate cluster properties
                cluster_pixels = delta_magnitude[labeled_array == i]
                avg_change = np.mean(cluster_pixels)
                
                text_regions.append({
                    'bbox': (x1, y1, x2, y2),
                    'area': area,
                    'avg_change': avg_change,
                    'width': width,
                    'height': height,
                    'center': ((x1 + x2) // 2, (y1 + y2) // 2)
                })
        
        # Sort by area (larger text regions first)
        text_regions.sort(key=lambda x: x['area'], reverse=True)
        return text_regions
        
    except ImportError:
        # Fallback: simple grid-based approach if scipy not available
        height, width = delta_magnitude.shape
        regions = []
        
        # Divide into larger grid cells and look for high change density
        rows, cols = 4, 6  
        cell_height = height // rows
        cell_width = width // cols
        
        for r in range(rows):
            for c in range(cols):
                y1 = r * cell_height
                y2 = min((r + 1) * cell_height, height)
                x1 = c * cell_width
                x2 = min((c + 1) * cell_width, width)
                
                cell_changes = changed_pixels[y1:y2, x1:x2]
                change_density = np.mean(cell_changes)
                
                if change_density > 0.1:  # At least 10% of pixels changed
                    avg_change = np.mean(delta_magnitude[y1:y2, x1:x2])
                    regions.append({
                        'bbox': (x1, y1, x2, y2),
                        'area': (x2-x1) * (y2-y1),
                        'avg_change': avg_change,
                        'width': x2-x1,
                        'height': y2-y1,
                        'center': ((x1 + x2) // 2, (y1 + y2) // 2)
                    })
        
        regions.sort(key=lambda x: x['avg_change'], reverse=True)
        return regions


def check_text_positioning(text_regions, img_size):
    """
    Check if detected text regions are positioned in lower center area.
    """
    width, height = img_size
    
    # Define lower center area (roughly bottom 40% and center 60% of image)
    lower_center_bounds = {
        'x_min': width * 0.2,   # 20% from left
        'x_max': width * 0.8,   # 80% from left  
        'y_min': height * 0.6,  # 60% from top (lower area)
        'y_max': height * 0.95  # 95% from top
    }
    
    positioned_correctly = False
    best_region = None
    
    for region in text_regions:
        center_x, center_y = region['center']
        
        # Check if region center is in lower center area
        if (lower_center_bounds['x_min'] <= center_x <= lower_center_bounds['x_max'] and
            lower_center_bounds['y_min'] <= center_y <= lower_center_bounds['y_max']):
            positioned_correctly = True
            best_region = region
            logging.debug(f"Found text region in lower center: {region}")
            break
    
    return positioned_correctly, best_region


def analyze_text_characteristics(result_img, text_regions):
    """
    Analyze characteristics of detected text regions.
    Look for evidence of white text with dark shadows/outlines.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    img_array = np.array(result_img)
    
    characteristics = {
        'has_white_text': False,
        'has_dark_outline': False,
        'text_size_adequate': False,
        'total_text_area': 0
    }
    
    total_area = 0
    
    for region in text_regions[:3]:  # Check top 3 most likely text regions
        x1, y1, x2, y2 = region['bbox']
        region_img = img_array[y1:y2, x1:x2]
        
        if region_img.size == 0:
            continue
            
        total_area += region['area']
        
        # Analyze colors in the region
        region_colors = region_img.reshape(-1, 3)
        
        # Look for white/light colors (potential text)
        light_pixels = np.sum(np.mean(region_colors, axis=1) > 180)  # Bright pixels
        dark_pixels = np.sum(np.mean(region_colors, axis=1) < 100)   # Dark pixels
        total_pixels = len(region_colors)
        
        light_ratio = light_pixels / total_pixels if total_pixels > 0 else 0
        dark_ratio = dark_pixels / total_pixels if total_pixels > 0 else 0
        
        # Check for white text (significant light pixels)
        if light_ratio > 0.12:  # At least 12% light pixels
            characteristics['has_white_text'] = True
            logging.debug(f"Found likely white text in region: light_ratio={light_ratio:.2f}")
        
        # Check for dark outline/shadow (mix of dark and light)
        if dark_ratio > 0.08 and light_ratio > 0.08:  # Both dark and light present
            characteristics['has_dark_outline'] = True
            logging.debug(f"Found likely text with outline: dark_ratio={dark_ratio:.2f}, light_ratio={light_ratio:.2f}")
        
        # Check text size (region should be reasonably sized)
        if region['width'] > 25 and region['height'] > 25:  # Reasonable text dimensions
            characteristics['text_size_adequate'] = True
            logging.debug(f"Found adequately sized text region: {region['width']}x{region['height']}")
    
    characteristics['total_text_area'] = total_area
    
    return characteristics


def check_text_overlay(traj, env_info, task_info):
    """
    Main verifier function for text overlay task.
    
    Args:
        traj: Trajectory data with episode information
        env_info: Environment information including episode directory and copy utilities
        task_info: Task information
        
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    
    # Get episode directory and copy utilities
    episode_dir = env_info.get("episode_dir")
    copy_from_env = env_info.get("copy_from_env")
    
    if not episode_dir:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No episode directory found"
        }
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy utilities available"
        }
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container paths - try different possible output filenames
        possible_results = [
            "/home/ga/Desktop/summer_vibes_overlay.jpg",
            "/home/ga/Desktop/summer_vibes_overlay.png",
            "/home/ga/Desktop/summer_vibes_overlay.jpeg"
        ]
        
        container_original = "/home/ga/Desktop/landscape_image.jpg"
        
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
            
            # Detect text regions using delta-based approach
            text_regions = detect_text_regions_by_delta(original_image, result_image)
            
            # Check if text is positioned in lower center area
            correctly_positioned, best_region = check_text_positioning(text_regions, result_image.size)
            
            # Analyze text characteristics
            text_characteristics = analyze_text_characteristics(result_image, text_regions)
            
            # Check if image was modified (simple pixel comparison)
            images_different = len(text_regions) > 0 or not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
            
            feedback_parts = []
            feedback_parts.append(f"Original size: {original_image.size}")
            feedback_parts.append(f"Result size: {result_image.size}")
            feedback_parts.append(f"Text regions detected: {len(text_regions)}")
            feedback_parts.append(f"Total text area: {text_characteristics['total_text_area']}")
            if best_region:
                feedback_parts.append(f"Best region: {best_region['width']}x{best_region['height']} at {best_region['center']}")
            feedback_parts.append(f"Positioned in lower center: {'✅' if correctly_positioned else '❌'}")
            feedback_parts.append(f"Has white text: {'✅' if text_characteristics['has_white_text'] else '❌'}")
            feedback_parts.append(f"Has dark outline/shadow: {'✅' if text_characteristics['has_dark_outline'] else '❌'}")
            feedback_parts.append(f"Adequate text size: {'✅' if text_characteristics['text_size_adequate'] else '❌'}")
            feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
            
            # Calculate success based on multiple criteria
            criteria_met = 0
            total_criteria = 5
            
            if correctly_positioned:
                criteria_met += 1
            if text_characteristics['has_white_text']:
                criteria_met += 1
            if text_characteristics['has_dark_outline']:
                criteria_met += 1
            if text_characteristics['text_size_adequate']:
                criteria_met += 1
            if images_different:
                criteria_met += 1
            
            # Require at least 4 out of 5 criteria for success
            success = criteria_met >= 4
            score = (criteria_met / total_criteria) * 100
            
            if success:
                feedback_parts.append("🎉 Text overlay added successfully!")
                return {
                    "passed": True,
                    "score": int(score),
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                feedback_parts.append(f"❌ Text overlay requirements not fully met ({criteria_met}/{total_criteria})")
                return {
                    "passed": False,
                    "score": int(score),
                    "feedback": " | ".join(feedback_parts)
                }
            
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error during verification: {str(e)}"
            }