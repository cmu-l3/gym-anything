#!/usr/bin/env python3
"""
Verifier for GIMP border stroke task.
Checks if a border was added to the image using stroke selection.
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


def analyze_edge_regions(img, border_width=30):
    """
    Analyze the edge regions of an image to detect borders.
    Returns statistics for top, bottom, left, right edges.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    height, width = img_array.shape[:2]
    
    # Define edge regions
    edges = {
        'top': img_array[0:border_width, :, :],
        'bottom': img_array[height-border_width:height, :, :],
        'left': img_array[:, 0:border_width, :],
        'right': img_array[:, width-border_width:width, :]
    }
    
    edge_stats = {}
    for edge_name, edge_region in edges.items():
        if edge_region.size > 0:
            # Calculate mean brightness (grayscale equivalent)
            grayscale_values = np.mean(edge_region, axis=2)
            mean_brightness = np.mean(grayscale_values)
            std_brightness = np.std(grayscale_values)
            
            edge_stats[edge_name] = {
                'mean_brightness': mean_brightness,
                'std_brightness': std_brightness,
                'shape': edge_region.shape
            }
        else:
            edge_stats[edge_name] = {
                'mean_brightness': 255,  # Assume bright if no data
                'std_brightness': 0,
                'shape': (0, 0, 0)
            }
    
    return edge_stats


def detect_border_stroke(original_img, result_img):
    """
    Detect if a border stroke was applied by analyzing edge region changes.
    """
    # Ensure images are the same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Analyze edge regions for both images
    original_edges = analyze_edge_regions(original_img)
    result_edges = analyze_edge_regions(result_img)
    
    analysis = {
        'edge_darkening': {},
        'center_preserved': False,
        'uniform_border': False,
        'border_detected': False
    }
    
    # Calculate darkening for each edge
    total_darkening = 0
    darkening_values = []
    
    for edge_name in ['top', 'bottom', 'left', 'right']:
        orig_brightness = original_edges[edge_name]['mean_brightness']
        result_brightness = result_edges[edge_name]['mean_brightness']
        
        # Calculate relative darkening
        if orig_brightness > 0:
            darkening_pct = (orig_brightness - result_brightness) / orig_brightness
        else:
            darkening_pct = 0
        
        analysis['edge_darkening'][edge_name] = darkening_pct
        darkening_values.append(darkening_pct)
        total_darkening += darkening_pct
    
    avg_darkening = total_darkening / 4
    darkening_std = np.std(darkening_values)
    
    # Check center preservation
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    height, width = orig_array.shape[:2]
    center_margin = 50
    if height > 2 * center_margin and width > 2 * center_margin:
        orig_center = orig_array[center_margin:height-center_margin, center_margin:width-center_margin]
        result_center = result_array[center_margin:height-center_margin, center_margin:width-center_margin]
        
        # Calculate difference in center region
        center_diff = np.mean(np.abs(orig_center.astype(float) - result_center.astype(float)))
        analysis['center_preserved'] = center_diff < 10  # Very small change allowed
    else:
        analysis['center_preserved'] = True  # Too small to have meaningful center
    
    # Check uniformity (low standard deviation = uniform border)
    analysis['uniform_border'] = darkening_std < 0.1
    
    # Overall border detection
    significant_darkening = avg_darkening >= 0.15  # At least 15% darker
    analysis['border_detected'] = significant_darkening and analysis['uniform_border']
    
    analysis['avg_darkening'] = avg_darkening
    analysis['darkening_std'] = darkening_std
    
    return analysis


def check_border_stroke(traj, env_info, task_info):
    """
    Main verifier function for border stroke task.
    Checks:
    1. Edge regions show significant darkening (border added)
    2. All four edges show similar darkening (uniform border)
    3. Center region is preserved (stroke didn't affect main content)
    4. Clear evidence of border structure
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
        "/home/ga/Desktop/photo_border.jpg",
        "/home/ga/Desktop/photo_for_border_edited.jpg",
        "/home/ga/Desktop/border_stroke.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_for_border.jpg",
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
        
        # Detect border stroke
        border_analysis = detect_border_stroke(original_image, result_image)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size or not np.array_equal(
            np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Average edge darkening: {border_analysis['avg_darkening']:.1%}")
        feedback_parts.append(f"Border uniformity (std): {border_analysis['darkening_std']:.3f}")
        
        # Individual edge analysis
        for edge, darkening in border_analysis['edge_darkening'].items():
            feedback_parts.append(f"{edge} edge darkening: {darkening:.1%}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant edge darkening (≥15%)
        edge_darkening_good = border_analysis['avg_darkening'] >= 0.15
        if edge_darkening_good:
            criteria_met += 1
        feedback_parts.append(f"Edge darkening (≥15%): {'✅' if edge_darkening_good else '❌'}")
        
        # 2. Uniform border across edges
        if border_analysis['uniform_border']:
            criteria_met += 1
        feedback_parts.append(f"Uniform border: {'✅' if border_analysis['uniform_border'] else '❌'}")
        
        # 3. Center preserved
        if border_analysis['center_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Center preserved: {'✅' if border_analysis['center_preserved'] else '❌'}")
        
        # 4. Border structure detected
        if border_analysis['border_detected']:
            criteria_met += 1
        feedback_parts.append(f"Border detected: {'✅' if border_analysis['border_detected'] else '❌'}")
        
        # Also check that image was modified
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent border stroke application!")
        elif passed:
            feedback_parts.append("✅ Good border stroke!")
        else:
            feedback_parts.append("❌ Border stroke needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in border stroke verification: {e}")
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
    result = check_border_stroke([], {}, {})
    print(f"Test result: {result}")