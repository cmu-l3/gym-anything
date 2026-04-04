#!/usr/bin/env python3
"""
Verifier for GIMP border frame task.
Checks if a decorative border/frame was added to the image.
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


def check_dimension_increase(original_img, result_img):
    """Check if image dimensions increased reasonably for border addition."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    width_increase = result_w - orig_w
    height_increase = result_h - orig_h
    
    # Border should increase both dimensions by at least 10px total (5px per side)
    # But not more than 200px total (100px per side would be excessive)
    reasonable_increase = (10 <= width_increase <= 200 and 
                          10 <= height_increase <= 200)
    
    return {
        'width_increase': width_increase,
        'height_increase': height_increase,
        'reasonable_increase': reasonable_increase
    }


def detect_border_regions(result_img):
    """
    Detect uniform border regions at image edges.
    Returns border analysis including uniformity and estimated width.
    """
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    img_array = np.array(result_img)
    height, width = img_array.shape[:2]
    
    def analyze_edge_uniformity(edge_region, edge_name):
        """Analyze color uniformity in an edge region."""
        if edge_region.size == 0:
            return {'uniform': False, 'variance': float('inf')}
        
        # Calculate color variance across the edge region
        edge_colors = edge_region.reshape(-1, 3)
        color_variance = np.var(edge_colors, axis=0)
        total_variance = np.sum(color_variance)
        
        # Low variance indicates uniform color (likely border)
        uniform = total_variance < 800  # Threshold for uniform color
        
        logging.debug(f"{edge_name} edge variance: {total_variance:.1f}, uniform: {uniform}")
        
        return {
            'uniform': uniform,
            'variance': total_variance,
            'mean_color': np.mean(edge_colors, axis=0)
        }
    
    # Sample edge regions to detect borders
    # Use adaptive sampling based on image size
    border_sample_width = min(max(width // 20, 15), 50)  # 5% of width, 15-50px range
    border_sample_height = min(max(height // 20, 15), 50)  # 5% of height, 15-50px range
    
    # Extract edge regions
    top_edge = img_array[:border_sample_height, :]
    bottom_edge = img_array[-border_sample_height:, :]
    left_edge = img_array[:, :border_sample_width]
    right_edge = img_array[:, -border_sample_width:]
    
    # Analyze uniformity of each edge
    edge_analyses = {
        'top': analyze_edge_uniformity(top_edge, 'Top'),
        'bottom': analyze_edge_uniformity(bottom_edge, 'Bottom'),
        'left': analyze_edge_uniformity(left_edge, 'Left'),
        'right': analyze_edge_uniformity(right_edge, 'Right')
    }
    
    # Count uniform edges
    uniform_edges = sum(1 for analysis in edge_analyses.values() if analysis['uniform'])
    
    # Estimate border width based on uniform regions
    estimated_border_width = max(border_sample_width, border_sample_height)
    
    return {
        'uniform_edges': uniform_edges,
        'total_edges': 4,
        'border_detected': uniform_edges >= 3,  # At least 3 edges should be uniform
        'estimated_width': estimated_border_width,
        'edge_analyses': edge_analyses
    }


def check_content_preservation(original_img, result_img, estimated_border_width):
    """
    Check if original image content is preserved in the center region.
    """
    try:
        from skimage.metrics import structural_similarity as ssim
    except ImportError:
        # Fallback to simple correlation if SSIM unavailable
        logging.warning("SSIM not available, using correlation fallback")
        return check_content_preservation_fallback(original_img, result_img, estimated_border_width)
    
    # Ensure same mode for comparison
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Extract center region from result image (accounting for border)
    margin = estimated_border_width + 5  # Add small margin for safety
    
    # Calculate center region bounds
    center_x1 = max(0, (result_w - orig_w) // 2)
    center_y1 = max(0, (result_h - orig_h) // 2)
    center_x2 = min(result_w, center_x1 + orig_w)
    center_y2 = min(result_h, center_y1 + orig_h)
    
    # Extract center region
    center_region = result_img.crop((center_x1, center_y1, center_x2, center_y2))
    
    # Resize if dimensions don't match exactly
    if center_region.size != original_img.size:
        center_region = center_region.resize(original_img.size, Image.Resampling.LANCZOS)
    
    # Convert to arrays for SSIM
    orig_array = np.array(original_img.convert('RGB'))
    center_array = np.array(center_region.convert('RGB'))
    
    # Calculate SSIM
    similarity = ssim(orig_array, center_array, 
                     win_size=7, multichannel=True, channel_axis=2)
    
    content_preserved = similarity >= 0.95  # High threshold for content preservation
    
    logging.debug(f"Content preservation SSIM: {similarity:.3f}")
    
    return {
        'similarity': similarity,
        'content_preserved': content_preserved,
        'center_region_size': center_region.size
    }


def check_content_preservation_fallback(original_img, result_img, estimated_border_width):
    """Fallback content preservation check using simple correlation."""
    # Simple pixel-wise comparison fallback
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Try to extract center and compare
    center_x1 = (result_w - orig_w) // 2
    center_y1 = (result_h - orig_h) // 2
    center_x2 = center_x1 + orig_w
    center_y2 = center_y1 + orig_h
    
    if center_x1 >= 0 and center_y1 >= 0 and center_x2 <= result_w and center_y2 <= result_h:
        center_region = result_img.crop((center_x1, center_y1, center_x2, center_y2))
        
        # Simple pixel correlation
        orig_array = np.array(original_img.convert('RGB'))
        center_array = np.array(center_region.convert('RGB'))
        
        if orig_array.shape == center_array.shape:
            correlation = np.corrcoef(orig_array.flatten(), center_array.flatten())[0, 1]
            content_preserved = correlation >= 0.95
        else:
            content_preserved = False
            correlation = 0.0
    else:
        content_preserved = False
        correlation = 0.0
    
    return {
        'similarity': correlation,
        'content_preserved': content_preserved,
        'center_region_size': (orig_w, orig_h) if content_preserved else (0, 0)
    }


def check_border_frame(traj, env_info, task_info):
    """
    Main verifier function for border frame task.
    Checks:
    1. Image dimensions increased reasonably (border adds size)
    2. Uniform border regions detected at edges
    3. Original content preserved in center
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
        "/home/ga/Desktop/bordered_image.jpg",
        "/home/ga/Desktop/bordered_image.png",
        "/home/ga/Desktop/bordered_image.jpeg",
        "/home/ga/Desktop/landscape_image_bordered.jpg",
        "/home/ga/Desktop/landscape_border.jpg",
        "/home/ga/Desktop/framed_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_image.jpg",
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
        
        # Check dimension increase
        dimension_check = check_dimension_increase(original_image, result_image)
        
        # Detect border regions
        border_analysis = detect_border_regions(result_image)
        
        # Check content preservation
        content_check = check_content_preservation(
            original_image, result_image, border_analysis['estimated_width']
        )
        
        # Check if image was modified
        images_different = (original_image.size != result_image.size or 
                          not np.array_equal(np.array(original_image), 
                                           np.array(result_image.convert(original_image.mode))))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Size increase: {dimension_check['width_increase']}×{dimension_check['height_increase']}")
        feedback_parts.append(f"Reasonable size increase: {'✅' if dimension_check['reasonable_increase'] else '❌'}")
        feedback_parts.append(f"Uniform edges detected: {border_analysis['uniform_edges']}/4")
        feedback_parts.append(f"Border detected: {'✅' if border_analysis['border_detected'] else '❌'}")
        feedback_parts.append(f"Content preserved (SSIM): {content_check['similarity']:.3f}")
        feedback_parts.append(f"Content preserved: {'✅' if content_check['content_preserved'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimension_check['reasonable_increase']:
            criteria_met += 1
        if border_analysis['border_detected']:
            criteria_met += 1
        if content_check['content_preserved']:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect border frame added!")
        elif passed:
            feedback_parts.append("✅ Good border frame added!")
        else:
            feedback_parts.append("❌ Border frame needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in border frame verification: {e}")
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
    result = check_border_frame([], {}, {})
    print(f"Test result: {result}")