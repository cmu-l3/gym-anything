#!/usr/bin/env python3
"""
Verifier for GIMP paintbrush drawing task.
Checks if visible brush strokes were created on the canvas using stroke detection.
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


def detect_brush_strokes(original_img, result_img):
    """
    Detect brush strokes by analyzing pixel differences between original and result images.
    Uses connected component analysis to identify individual stroke regions.
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
    
    # Calculate pixel-wise differences
    delta = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate magnitude of change for each pixel
    magnitude = np.sqrt(np.sum(delta ** 2, axis=2))
    
    # Threshold for significant changes (likely brush strokes)
    threshold = max(np.percentile(magnitude, 95), 20)  # Top 5% of changes or min 20 units
    stroke_mask = magnitude > threshold
    
    # Connected component analysis for individual strokes
    try:
        from scipy.ndimage import label
        labeled_strokes, num_strokes = label(stroke_mask)
        
        stroke_regions = []
        for i in range(1, num_strokes + 1):
            region_mask = (labeled_strokes == i)
            area = np.sum(region_mask)
            
            # Filter out noise (very small regions)
            if area >= 50:  # Minimum stroke area
                # Get bounding box
                coords = np.where(region_mask)
                y_min, y_max = np.min(coords[0]), np.max(coords[0])
                x_min, x_max = np.min(coords[1]), np.max(coords[1])
                
                stroke_regions.append({
                    'area': area,
                    'mask': region_mask,
                    'avg_intensity': np.mean(magnitude[region_mask]),
                    'bbox': (x_min, y_min, x_max, y_max),
                    'width': x_max - x_min + 1,
                    'height': y_max - y_min + 1,
                    'center': (int((x_min + x_max) / 2), int((y_min + y_max) / 2))
                })
        
        # Sort by area (largest strokes first)
        stroke_regions.sort(key=lambda x: x['area'], reverse=True)
        return stroke_regions, stroke_mask
        
    except ImportError:
        # Fallback analysis without scipy
        logging.warning("SciPy not available, using basic stroke detection")
        total_changed_pixels = np.sum(stroke_mask)
        estimated_regions = []
        
        if total_changed_pixels > 100:  # Some meaningful change
            # Simple grid-based approach to estimate stroke regions
            height, width = stroke_mask.shape
            rows, cols = 4, 4
            cell_height = height // rows
            cell_width = width // cols
            
            for r in range(rows):
                for c in range(cols):
                    y1 = r * cell_height
                    y2 = min((r + 1) * cell_height, height)
                    x1 = c * cell_width
                    x2 = min((c + 1) * cell_width, width)
                    
                    cell_strokes = stroke_mask[y1:y2, x1:x2]
                    cell_area = np.sum(cell_strokes)
                    
                    if cell_area > 25:  # Minimum area per cell
                        estimated_regions.append({
                            'area': cell_area,
                            'estimated': True,
                            'bbox': (x1, y1, x2, y2),
                            'center': ((x1 + x2) // 2, (y1 + y2) // 2)
                        })
            
            estimated_regions.sort(key=lambda x: x['area'], reverse=True)
        
        return estimated_regions, stroke_mask


def analyze_stroke_coverage(stroke_mask, img_size):
    """
    Analyze coverage and distribution of brush strokes.
    """
    width, height = img_size
    total_pixels = width * height
    stroke_pixels = np.sum(stroke_mask)
    
    coverage_percentage = (stroke_pixels / total_pixels) * 100
    
    # Check distribution across canvas (avoid clustering in tiny area)
    if stroke_pixels > 0:
        coords = np.where(stroke_mask)
        y_coords, x_coords = coords[0], coords[1]
        
        # Calculate spread
        x_spread = np.max(x_coords) - np.min(x_coords)
        y_spread = np.max(y_coords) - np.min(y_coords)
        
        # Normalized spread (0-1)
        x_spread_norm = x_spread / width
        y_spread_norm = y_spread / height
        
        well_distributed = x_spread_norm > 0.15 and y_spread_norm > 0.15  # At least 15% spread
    else:
        well_distributed = False
        x_spread_norm = 0
        y_spread_norm = 0
    
    return {
        'coverage_percentage': coverage_percentage,
        'well_distributed': well_distributed,
        'x_spread_norm': x_spread_norm,
        'y_spread_norm': y_spread_norm,
        'stroke_pixels': stroke_pixels
    }


def analyze_stroke_visibility(original_img, result_img, stroke_regions):
    """
    Analyze visibility and contrast of brush strokes.
    """
    if not stroke_regions:
        return {'visible': False, 'good_contrast': False}
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    total_contrast_score = 0
    regions_analyzed = 0
    
    for region in stroke_regions[:5]:  # Analyze top 5 regions
        if 'mask' not in region:  # Skip estimated regions
            continue
            
        mask = region['mask']
        
        # Get colors in stroke region
        stroke_pixels = result_array[mask]
        original_pixels = orig_array[mask]
        
        if len(stroke_pixels) == 0:
            continue
            
        # Calculate average colors
        avg_stroke_color = np.mean(stroke_pixels, axis=0)
        avg_original_color = np.mean(original_pixels, axis=0)
        
        # Calculate contrast (color difference)
        color_diff = np.sqrt(np.sum((avg_stroke_color - avg_original_color) ** 2))
        
        total_contrast_score += color_diff
        regions_analyzed += 1
    
    if regions_analyzed > 0:
        avg_contrast = total_contrast_score / regions_analyzed
        good_contrast = avg_contrast > 30  # Threshold for visible contrast
        visible = True
    else:
        avg_contrast = 0
        good_contrast = False
        visible = False
    
    return {
        'visible': visible,
        'good_contrast': good_contrast,
        'avg_contrast': avg_contrast,
        'regions_analyzed': regions_analyzed
    }


def check_paintbrush_drawing(traj, env_info, task_info):
    """
    Main verifier function for paintbrush drawing task.
    Checks:
    1. Visible brush strokes were created on the canvas
    2. Multiple distinct stroke regions exist
    3. Adequate coverage of canvas area
    4. Good contrast and visibility
    5. Proper distribution across canvas
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
        "/home/ga/Desktop/paintbrush_drawing.png",
        "/home/ga/Desktop/paintbrush_drawing.jpg",
        "/home/ga/Desktop/paintbrush_drawing.jpeg",
        "/home/ga/Desktop/brush_drawing.png",
        "/home/ga/Desktop/drawing.png",
        "/home/ga/Desktop/blank_canvas_edited.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/blank_canvas.png",
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
        
        # Detect brush strokes
        stroke_regions, stroke_mask = detect_brush_strokes(original_image, result_image)
        
        # Analyze coverage and distribution
        coverage_analysis = analyze_stroke_coverage(stroke_mask, result_image.size)
        
        # Analyze visibility and contrast
        visibility_analysis = analyze_stroke_visibility(original_image, result_image, stroke_regions)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Stroke regions detected: {len(stroke_regions)}")
        feedback_parts.append(f"Coverage: {coverage_analysis['coverage_percentage']:.1f}%")
        feedback_parts.append(f"Well distributed: {'✅' if coverage_analysis['well_distributed'] else '❌'}")
        if visibility_analysis['regions_analyzed'] > 0:
            feedback_parts.append(f"Avg contrast: {visibility_analysis['avg_contrast']:.1f}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Multiple stroke regions detected
        multiple_strokes = len(stroke_regions) >= 3
        if multiple_strokes:
            criteria_met += 1
        feedback_parts.append(f"Multiple strokes (≥3): {'✅' if multiple_strokes else '❌'}")
        
        # 2. Adequate coverage (at least 5% of canvas)
        adequate_coverage = coverage_analysis['coverage_percentage'] >= 5.0
        if adequate_coverage:
            criteria_met += 1
        feedback_parts.append(f"Adequate coverage (≥5%): {'✅' if adequate_coverage else '❌'}")
        
        # 3. Good distribution (not clustered in tiny area)
        if coverage_analysis['well_distributed']:
            criteria_met += 1
        
        # 4. Good contrast/visibility
        if visibility_analysis['good_contrast']:
            criteria_met += 1
        feedback_parts.append(f"Good contrast: {'✅' if visibility_analysis['good_contrast'] else '❌'}")
        
        # 5. Image was modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent paintbrush drawing!")
        elif passed:
            feedback_parts.append("✅ Good paintbrush drawing!")
        else:
            feedback_parts.append("❌ Paintbrush drawing needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in paintbrush drawing verification: {e}")
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
    result = check_paintbrush_drawing([], {}, {})
    print(f"Test result: {result}")