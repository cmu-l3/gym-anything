#!/usr/bin/env python3
"""
Verifier for GIMP brush drawing task.
Checks if visible brush strokes were painted on the canvas.
"""

import logging
import tempfile
from pathlib import Path
from PIL import Image
import numpy as np
import sys
import os

logging.basicConfig(level=logging.DEBUG)


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def detect_brush_strokes(original_img, result_img):
    """
    Detect painted areas using delta analysis and morphological operations.
    Returns information about detected paint strokes.
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
    magnitude = np.sqrt(np.sum(delta ** 2, axis=2))
    
    # Threshold for significant paint changes
    paint_threshold = 30
    painted_pixels = magnitude > paint_threshold
    
    # Calculate basic statistics
    total_pixels = painted_pixels.size
    painted_pixel_count = np.sum(painted_pixels)
    coverage_percentage = (painted_pixel_count / total_pixels) * 100
    
    # Try to use scipy for advanced analysis
    stroke_regions = []
    try:
        from scipy.ndimage import binary_opening, binary_closing, label
        
        # Clean up noise while preserving stroke structure
        cleaned = binary_opening(painted_pixels, structure=np.ones((3,3)))
        cleaned = binary_closing(cleaned, structure=np.ones((5,5)))
        
        # Identify connected stroke regions
        labeled_strokes, num_strokes = label(cleaned)
        
        for i in range(1, num_strokes + 1):
            stroke_mask = (labeled_strokes == i)
            area = np.sum(stroke_mask)
            
            if area >= 50:  # Minimum stroke size
                y_coords, x_coords = np.where(stroke_mask)
                bbox = (np.min(x_coords), np.min(y_coords), 
                       np.max(x_coords), np.max(y_coords))
                
                # Calculate stroke characteristics
                width = bbox[2] - bbox[0]
                height = bbox[3] - bbox[1]
                center = ((bbox[0] + bbox[2]) // 2, (bbox[1] + bbox[3]) // 2)
                avg_intensity = np.mean(magnitude[stroke_mask])
                
                stroke_regions.append({
                    'area': area,
                    'bbox': bbox,
                    'width': width,
                    'height': height,
                    'center': center,
                    'avg_intensity': avg_intensity
                })
        
        # Sort by area (largest strokes first)
        stroke_regions.sort(key=lambda x: x['area'], reverse=True)
        
    except ImportError:
        # Fallback without scipy - simple grid analysis
        logging.warning("scipy not available, using basic analysis")
        height, width = magnitude.shape
        
        # Divide into grid and look for painted areas
        rows, cols = 6, 8
        cell_height = height // rows
        cell_width = width // cols
        
        for r in range(rows):
            for c in range(cols):
                y1 = r * cell_height
                y2 = min((r + 1) * cell_height, height)
                x1 = c * cell_width
                x2 = min((c + 1) * cell_width, width)
                
                cell_painted = painted_pixels[y1:y2, x1:x2]
                cell_paint_ratio = np.mean(cell_painted)
                
                if cell_paint_ratio > 0.1:  # At least 10% painted
                    cell_area = (x2-x1) * (y2-y1)
                    cell_avg_intensity = np.mean(magnitude[y1:y2, x1:x2])
                    
                    stroke_regions.append({
                        'area': cell_area * cell_paint_ratio,
                        'bbox': (x1, y1, x2, y2),
                        'width': x2-x1,
                        'height': y2-y1,
                        'center': ((x1 + x2) // 2, (y1 + y2) // 2),
                        'avg_intensity': cell_avg_intensity
                    })
    
    return {
        'coverage_percentage': coverage_percentage,
        'painted_pixels': painted_pixel_count,
        'total_pixels': total_pixels,
        'stroke_regions': stroke_regions,
        'num_strokes': len(stroke_regions)
    }


def analyze_stroke_characteristics(stroke_regions, img_size):
    """
    Analyze characteristics of detected stroke regions.
    """
    if not stroke_regions:
        return {
            'has_substantial_strokes': False,
            'has_multiple_strokes': False,
            'good_distribution': False,
            'adequate_size': False
        }
    
    width, height = img_size
    
    # Check for substantial strokes (reasonably sized)
    substantial_strokes = [s for s in stroke_regions if s['area'] >= 100]
    has_substantial = len(substantial_strokes) > 0
    
    # Check for multiple distinct strokes
    has_multiple = len(stroke_regions) >= 2
    
    # Check distribution across canvas
    centers = [s['center'] for s in stroke_regions[:5]]  # Top 5 strokes
    good_distribution = len(centers) >= 2
    if len(centers) >= 2:
        # Check if strokes are spread out (not all clustered)
        min_distance = min(
            abs(c1[0] - c2[0]) + abs(c1[1] - c2[1])
            for i, c1 in enumerate(centers)
            for c2 in centers[i+1:]
        ) if len(centers) > 1 else 0
        good_distribution = min_distance > min(width, height) * 0.1
    
    # Check if largest strokes are adequately sized
    largest_stroke_area = max([s['area'] for s in stroke_regions]) if stroke_regions else 0
    adequate_size = largest_stroke_area >= 200  # Reasonable brush stroke size
    
    return {
        'has_substantial_strokes': has_substantial,
        'has_multiple_strokes': has_multiple,
        'good_distribution': good_distribution,
        'adequate_size': adequate_size,
        'largest_stroke_area': largest_stroke_area,
        'substantial_stroke_count': len(substantial_strokes)
    }


def check_brush_drawing(traj, env_info, task_info):
    """
    Main verifier function for brush drawing task.
    Checks:
    1. Substantial paint coverage (at least 1% of canvas)
    2. Coherent brush strokes detected
    3. Multiple distinct stroke areas
    4. Good contrast and visibility
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
        
        # Define possible result paths
        possible_results = [
            "/home/ga/Desktop/brush_painting.jpg",
            "/home/ga/Desktop/brush_painting.png",
            "/home/ga/Desktop/brush_painting.jpeg",
            "/home/ga/Desktop/blank_canvas_painted.jpg",
            "/home/ga/Desktop/painting.jpg"
        ]
        
        container_original = "/home/ga/Desktop/blank_canvas.jpg"
        
        # Define host paths
        host_original = temp_path / "original.jpg"
        host_result = temp_path / "result.jpg"
        
        # Try to copy original canvas from container
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original canvas: {error}"
            }
        
        # Try to copy result image from container (try multiple possible names)
        result_found = False
        result_container_path = ""
        for result_path in possible_results:
            success, error = copy_file_from_container(copy_from_env, result_path, host_result)
            if success:
                result_found = True
                result_container_path = result_path
                logging.debug(f"Found result image at: {result_path}")
                break
        
        if not result_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access painted image. Expected: brush_painting.jpg"
            }
        
        try:
            # Load images from copied files
            original_image = Image.open(host_original)
            result_image = Image.open(host_result)
            
            logging.debug(f"Found result image at: {result_container_path}")
            
            # Detect brush strokes
            paint_analysis = detect_brush_strokes(original_image, result_image)
            
            # Analyze stroke characteristics
            stroke_characteristics = analyze_stroke_characteristics(
                paint_analysis['stroke_regions'], 
                result_image.size
            )
            
            # Check if image was modified
            images_different = not np.array_equal(
                np.array(original_image.convert('RGB')), 
                np.array(result_image.convert('RGB'))
            )
            
            feedback_parts = []
            feedback_parts.append(f"Canvas size: {original_image.size}")
            feedback_parts.append(f"Paint coverage: {paint_analysis['coverage_percentage']:.2f}%")
            feedback_parts.append(f"Stroke regions detected: {paint_analysis['num_strokes']}")
            feedback_parts.append(f"Largest stroke area: {stroke_characteristics['largest_stroke_area']}")
            feedback_parts.append(f"Substantial strokes: {'✅' if stroke_characteristics['has_substantial_strokes'] else '❌'}")
            feedback_parts.append(f"Multiple strokes: {'✅' if stroke_characteristics['has_multiple_strokes'] else '❌'}")
            feedback_parts.append(f"Good distribution: {'✅' if stroke_characteristics['good_distribution'] else '❌'}")
            feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
            
            # Calculate success based on multiple criteria
            criteria_met = 0
            total_criteria = 4
            
            # 1. Substantial paint coverage (at least 1%)
            if paint_analysis['coverage_percentage'] >= 1.0:
                criteria_met += 1
            
            # 2. Has substantial brush strokes
            if stroke_characteristics['has_substantial_strokes']:
                criteria_met += 1
            
            # 3. Good contrast (image was meaningfully changed)
            if images_different and paint_analysis['coverage_percentage'] >= 0.5:
                criteria_met += 1
            
            # 4. Multiple distinct strokes or good distribution
            if stroke_characteristics['has_multiple_strokes'] or stroke_characteristics['good_distribution']:
                criteria_met += 1
            
            # Score based on criteria met
            score = int((criteria_met / total_criteria) * 100)
            passed = score >= 75  # Need at least 3/4 criteria
            
            if passed and score >= 90:
                feedback_parts.append("🎉 Excellent brush painting!")
            elif passed:
                feedback_parts.append("✅ Good brush work!")
            else:
                feedback_parts.append("❌ Brush painting needs improvement")
                
            return {
                "passed": passed,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
            
        except Exception as e:
            logging.error(f"Error in brush drawing verification: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: {str(e)}"
            }


if __name__ == "__main__":
    # Test the verifier
    result = check_brush_drawing([], {}, {})
    print(f"Test result: {result}")