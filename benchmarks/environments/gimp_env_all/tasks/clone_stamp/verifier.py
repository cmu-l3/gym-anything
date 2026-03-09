#!/usr/bin/env python3
"""
Verifier for GIMP clone tool task.
Checks if the clone tool was used to remove/cover the red-marked target area.
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


def detect_red_target_area(img):
    """
    Detect the red-marked target area that should be cloned over.
    Returns bounding box coordinates of the red area.
    """
    if img.mode != 'RGB':
        img = img.convert('RGB')
    
    img_array = np.array(img)
    
    # Define red color range (for the marker)
    red_lower = np.array([180, 0, 0])    # Lower bound for red
    red_upper = np.array([255, 80, 80])  # Upper bound for red
    
    # Create mask for red pixels
    red_mask = ((img_array[:, :, 0] >= red_lower[0]) & (img_array[:, :, 0] <= red_upper[0]) &
                (img_array[:, :, 1] >= red_lower[1]) & (img_array[:, :, 1] <= red_upper[1]) &
                (img_array[:, :, 2] >= red_lower[2]) & (img_array[:, :, 2] <= red_upper[2]))
    
    if not np.any(red_mask):
        # If no red area found, assume center area as fallback
        h, w = img_array.shape[:2]
        return {
            'bbox': (w//2 - 50, h//2 - 50, w//2 + 50, h//2 + 50),
            'area': 10000,
            'found_marker': False
        }
    
    # Find bounding box of red area
    red_coords = np.where(red_mask)
    y_min, y_max = np.min(red_coords[0]), np.max(red_coords[0])
    x_min, x_max = np.min(red_coords[1]), np.max(red_coords[1])
    
    # Expand slightly to ensure we cover the target area
    padding = 10
    y_min = max(0, y_min - padding)
    y_max = min(img_array.shape[0], y_max + padding)
    x_min = max(0, x_min - padding)
    x_max = min(img_array.shape[1], x_max + padding)
    
    area = (x_max - x_min) * (y_max - y_min)
    
    return {
        'bbox': (x_min, y_min, x_max, y_min),
        'area': area,
        'found_marker': True
    }


def analyze_cloning_changes(original_img, result_img, target_area):
    """
    Analyze changes in the target area to detect cloning activity.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    change_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    
    # Extract target area
    x1, y1, x2, y2 = target_area['bbox']
    target_changes = change_magnitude[y1:y2, x1:x2]
    
    # Calculate metrics for target area
    if target_changes.size == 0:
        return {
            'target_modified': False,
            'change_percentage': 0,
            'avg_change': 0,
            'significant_changes': 0
        }
    
    avg_change = np.mean(target_changes)
    significant_threshold = 20  # Pixels with >20 intensity change
    significant_changes = np.sum(target_changes > significant_threshold)
    change_percentage = (significant_changes / target_changes.size) * 100
    
    target_modified = change_percentage >= 30  # At least 30% of target area changed
    
    return {
        'target_modified': target_modified,
        'change_percentage': change_percentage,
        'avg_change': avg_change,
        'significant_changes': significant_changes,
        'total_target_pixels': target_changes.size
    }


def analyze_source_target_similarity(original_img, result_img, target_area):
    """
    Analyze similarity between potential source areas and the modified target area.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    x1, y1, x2, y2 = target_area['bbox']
    
    # Extract target area from result image
    target_region = result_array[y1:y2, x1:x2]
    
    if target_region.size == 0:
        return {'similarity_score': 0, 'has_similarity': False}
    
    # Sample multiple potential source areas around the target
    h, w = orig_array.shape[:2]
    target_h, target_w = target_region.shape[:2]
    
    best_similarity = 0
    
    # Check several potential source areas
    offsets = [(-80, 0), (80, 0), (0, -80), (0, 80), (-60, -60), (60, 60)]
    
    for dx, dy in offsets:
        src_x1 = max(0, x1 + dx)
        src_y1 = max(0, y1 + dy)
        src_x2 = min(w, src_x1 + target_w)
        src_y2 = min(h, src_y1 + target_h)
        
        if src_x2 > src_x1 and src_y2 > src_y1:
            source_region = orig_array[src_y1:src_y2, src_x1:src_x2]
            
            # Resize to match target if needed
            if source_region.shape != target_region.shape:
                continue
            
            # Calculate normalized cross-correlation
            source_flat = source_region.flatten().astype(np.float32)
            target_flat = target_region.flatten().astype(np.float32)
            
            if len(source_flat) > 0 and len(target_flat) > 0:
                correlation = np.corrcoef(source_flat, target_flat)[0, 1]
                if not np.isnan(correlation):
                    best_similarity = max(best_similarity, correlation)
    
    has_similarity = best_similarity >= 0.3  # At least moderate similarity
    
    return {
        'similarity_score': best_similarity,
        'has_similarity': has_similarity
    }


def check_overall_modification(original_img, result_img):
    """Check if the image was meaningfully modified."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate overall difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of changed pixels
    change_magnitude = np.sqrt(np.sum(diff ** 2, axis=2))
    changed_pixels = np.sum(change_magnitude > 15)  # Pixels with >15 intensity change
    total_pixels = orig_array.shape[0] * orig_array.shape[1]
    change_percentage = (changed_pixels / total_pixels) * 100
    
    meaningfully_changed = change_percentage >= 1  # At least 1% of image changed
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_changed': meaningfully_changed
    }


def check_clone_stamp(traj, env_info, task_info):
    """
    Main verifier function for clone tool task.
    Checks:
    1. Target area was modified (cloning detected)
    2. Modifications show similarity to source texture
    3. Coverage is adequate
    4. Image was meaningfully changed
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
        "/home/ga/Desktop/cloned_result.jpg",
        "/home/ga/Desktop/cloned_result.png",
        "/home/ga/Desktop/cloned_result.jpeg",
        "/home/ga/Desktop/landscape_with_object_cloned.jpg",
        "/home/ga/Desktop/result.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/landscape_with_object.jpg",
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
        
        # Detect red target area in original image
        target_area = detect_red_target_area(original_image)
        
        # Analyze cloning changes in target area
        change_analysis = analyze_cloning_changes(original_image, result_image, target_area)
        
        # Analyze source-target similarity
        similarity_analysis = analyze_source_target_similarity(original_image, result_image, target_area)
        
        # Check overall modification
        modification_analysis = check_overall_modification(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Target area found: {'✅' if target_area['found_marker'] else '❌ (fallback)'}")
        feedback_parts.append(f"Target area: {target_area['bbox']}")
        feedback_parts.append(f"Change in target: {change_analysis['change_percentage']:.1f}%")
        feedback_parts.append(f"Source similarity: {similarity_analysis['similarity_score']:.2f}")
        feedback_parts.append(f"Overall change: {modification_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Target area was modified (cloning activity detected)
        if change_analysis['target_modified']:
            criteria_met += 1
        feedback_parts.append(f"Target area modified: {'✅' if change_analysis['target_modified'] else '❌'}")
        
        # 2. Source-target similarity indicates texture copying
        if similarity_analysis['has_similarity']:
            criteria_met += 1
        feedback_parts.append(f"Source-target similarity: {'✅' if similarity_analysis['has_similarity'] else '❌'}")
        
        # 3. Adequate coverage (at least 30% of target area changed)
        adequate_coverage = change_analysis['change_percentage'] >= 30
        if adequate_coverage:
            criteria_met += 1
        feedback_parts.append(f"Adequate coverage: {'✅' if adequate_coverage else '❌'}")
        
        # 4. Image was meaningfully modified
        if modification_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if modification_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent clone tool usage!")
        elif passed:
            feedback_parts.append("✅ Good clone tool application!")
        else:
            feedback_parts.append("❌ Clone tool usage needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in clone tool verification: {e}")
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
    result = check_clone_stamp([], {}, {})
    print(f"Test result: {result}")