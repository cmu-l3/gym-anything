#!/usr/bin/env python3
"""
Verifier for GIMP clone tool duplication task.
Checks if an element was successfully cloned/duplicated to another location in the image.
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

# Try to import OpenCV for advanced template matching
try:
    import cv2
    HAS_OPENCV = True
    logging.debug("OpenCV available for advanced template matching")
except ImportError:
    HAS_OPENCV = False
    logging.warning("OpenCV not available, using basic duplication detection")


def detect_duplications_opencv(result_img, min_template_size=30, correlation_threshold=0.7, min_distance=50):
    """
    Detect duplicated content using OpenCV template matching.
    Returns list of potential duplication matches.
    """
    if not HAS_OPENCV:
        return []
    
    # Convert PIL image to OpenCV format
    img_array = np.array(result_img.convert('RGB'))
    img_bgr = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    
    h, w = gray.shape
    duplications = []
    
    # Scan for potential template regions with different sizes
    template_sizes = [min_template_size, min_template_size + 20, min_template_size + 40]
    
    for template_size in template_sizes:
        # Skip if image too small for this template size
        if h < template_size + 20 or w < template_size + 20:
            continue
            
        step_size = max(20, template_size // 2)  # Adaptive step size
        
        for y in range(0, h - template_size, step_size):
            for x in range(0, w - template_size, step_size):
                # Extract template region
                template = gray[y:y+template_size, x:x+template_size]
                
                # Skip regions with low variation (likely background)
                if np.std(template) < 15:
                    continue
                
                # Perform template matching
                try:
                    result = cv2.matchTemplate(gray, template, cv2.TM_CCOEFF_NORMED)
                    
                    # Find matches above threshold
                    locations = np.where(result >= correlation_threshold)
                    
                    if len(locations[0]) >= 2:  # At least source + 1 clone
                        matches = list(zip(locations[1], locations[0]))  # (x, y) format
                        
                        # Filter out overlapping matches (require spatial separation)
                        filtered_matches = []
                        for match_x, match_y in matches:
                            # Check distance from template source
                            dist_from_source = np.sqrt((match_x - x)**2 + (match_y - y)**2)
                            
                            # Skip the source match itself (distance < 10)
                            if dist_from_source < 10:
                                continue
                                
                            # Ensure minimum distance from source
                            if dist_from_source >= min_distance:
                                # Check distance from other filtered matches
                                too_close = False
                                for existing_x, existing_y in filtered_matches:
                                    dist = np.sqrt((match_x - existing_x)**2 + (match_y - existing_y)**2)
                                    if dist < min_distance:
                                        too_close = True
                                        break
                                
                                if not too_close:
                                    filtered_matches.append((match_x, match_y))
                        
                        if len(filtered_matches) >= 1:  # At least one good clone
                            max_correlation = np.max(result)
                            duplications.append({
                                'source_location': (x, y),
                                'clone_matches': filtered_matches,
                                'max_correlation': max_correlation,
                                'template_size': template_size,
                                'total_area': template_size * template_size * (len(filtered_matches) + 1)
                            })
                
                except cv2.error as e:
                    logging.debug(f"OpenCV template matching error: {e}")
                    continue
    
    # Sort by quality metrics (correlation * area)
    duplications.sort(key=lambda x: x['max_correlation'] * x['template_size'], reverse=True)
    
    return duplications


def detect_duplications_basic(result_img, original_img):
    """
    Basic duplication detection using simple pixel differences and clustering.
    Fallback when OpenCV is not available.
    """
    # Convert to grayscale for analysis
    result_gray = np.array(result_img.convert('L'))
    
    h, w = result_gray.shape
    
    # Simple approach: look for repeated patterns in image regions
    duplications = []
    
    # Divide image into overlapping regions and compare
    region_size = 40
    step_size = 20
    
    regions = []
    for y in range(0, h - region_size, step_size):
        for x in range(0, w - region_size, step_size):
            region = result_gray[y:y+region_size, x:x+region_size]
            if np.std(region) > 10:  # Skip uniform regions
                regions.append({
                    'data': region,
                    'location': (x, y),
                    'std': np.std(region)
                })
    
    # Compare regions to find similar ones
    similarity_threshold = 0.8
    min_distance = 50
    
    for i, region1 in enumerate(regions):
        matches = []
        for j, region2 in enumerate(regions[i+1:], i+1):
            # Calculate distance between regions
            dist = np.sqrt((region1['location'][0] - region2['location'][0])**2 + 
                          (region1['location'][1] - region2['location'][1])**2)
            
            if dist >= min_distance:
                # Calculate normalized cross-correlation
                corr = np.corrcoef(region1['data'].flatten(), region2['data'].flatten())[0, 1]
                
                if not np.isnan(corr) and corr >= similarity_threshold:
                    matches.append({
                        'location': region2['location'],
                        'correlation': corr,
                        'distance': dist
                    })
        
        if len(matches) >= 1:
            duplications.append({
                'source_location': region1['location'],
                'clone_matches': [m['location'] for m in matches],
                'max_correlation': max(m['correlation'] for m in matches),
                'template_size': region_size,
                'total_area': region_size * region_size * (len(matches) + 1)
            })
    
    # Sort by correlation
    duplications.sort(key=lambda x: x['max_correlation'], reverse=True)
    
    return duplications


def analyze_duplication_quality(duplications, img_size):
    """
    Analyze the quality and characteristics of detected duplications.
    """
    if not duplications:
        return {
            'duplication_detected': False,
            'adequate_coverage': False,
            'high_similarity': False,
            'spatial_separation': False,
            'total_duplicated_area': 0,
            'best_correlation': 0
        }
    
    best_duplication = duplications[0]
    total_area = sum(d['total_area'] for d in duplications[:3])  # Top 3 duplications
    best_correlation = best_duplication['max_correlation']
    
    # Check coverage (should be meaningful size)
    adequate_coverage = total_area >= 200  # At least 200 pixels total
    
    # Check correlation quality
    high_similarity = best_correlation >= 0.7
    
    # Check spatial separation (already ensured in detection)
    spatial_separation = len(best_duplication['clone_matches']) >= 1
    
    return {
        'duplication_detected': True,
        'adequate_coverage': adequate_coverage,
        'high_similarity': high_similarity,
        'spatial_separation': spatial_separation,
        'total_duplicated_area': total_area,
        'best_correlation': best_correlation,
        'num_duplications': len(duplications),
        'best_template_size': best_duplication['template_size']
    }


def check_image_modified(original_img, result_img):
    """Check if the image was meaningfully modified."""
    # Ensure same size for comparison
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same mode
    if original_img.mode != result_img.mode:
        result_img = result_img.convert(original_img.mode)
    
    # Calculate pixel differences
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Calculate mean absolute difference
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    mean_diff = np.mean(diff)
    
    # Calculate percentage of significantly changed pixels
    if len(diff.shape) == 3:  # Color image
        pixel_diff = np.sqrt(np.sum(diff ** 2, axis=2))
    else:  # Grayscale
        pixel_diff = diff
    
    significantly_changed = np.sum(pixel_diff > 30)
    total_pixels = pixel_diff.shape[0] * pixel_diff.shape[1]
    change_percentage = (significantly_changed / total_pixels) * 100
    
    return {
        'mean_difference': mean_diff,
        'change_percentage': change_percentage,
        'meaningfully_modified': change_percentage > 1.0  # At least 1% of pixels changed significantly
    }


def check_clone_duplicate(traj, env_info, task_info):
    """
    Main verifier function for clone duplication task.
    Checks:
    1. Duplication was detected using template matching
    2. Cloned content has adequate coverage
    3. Similarity between source and clone is high
    4. Cloned content is spatially separated from source
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
        "/home/ga/Desktop/cloned_element.jpg",
        "/home/ga/Desktop/cloned_element.png", 
        "/home/ga/Desktop/cloned_element.jpeg",
        "/home/ga/Desktop/clone_scene_cloned.jpg",
        "/home/ga/Desktop/clone_result.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/clone_scene.jpg",
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
        
        # Detect duplications using template matching
        if HAS_OPENCV:
            duplications = detect_duplications_opencv(result_image)
            detection_method = "OpenCV template matching"
        else:
            duplications = detect_duplications_basic(result_image, original_image)
            detection_method = "Basic correlation analysis"
        
        # Analyze duplication quality
        quality_analysis = analyze_duplication_quality(duplications, result_image.size)
        
        # Check if image was modified
        modification_analysis = check_image_modified(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Detection method: {detection_method}")
        feedback_parts.append(f"Duplications found: {quality_analysis['num_duplications']}")
        feedback_parts.append(f"Total duplicated area: {quality_analysis['total_duplicated_area']}")
        feedback_parts.append(f"Best correlation: {quality_analysis['best_correlation']:.3f}")
        feedback_parts.append(f"Pixels changed: {modification_analysis['change_percentage']:.1f}%")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if quality_analysis['duplication_detected']:
            criteria_met += 1
        feedback_parts.append(f"Duplication detected: {'✅' if quality_analysis['duplication_detected'] else '❌'}")
        
        if quality_analysis['adequate_coverage']:
            criteria_met += 1
        feedback_parts.append(f"Adequate coverage: {'✅' if quality_analysis['adequate_coverage'] else '❌'}")
        
        if quality_analysis['high_similarity']:
            criteria_met += 1
        feedback_parts.append(f"High similarity: {'✅' if quality_analysis['high_similarity'] else '❌'}")
        
        if quality_analysis['spatial_separation']:
            criteria_met += 1
        feedback_parts.append(f"Spatial separation: {'✅' if quality_analysis['spatial_separation'] else '❌'}")
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent cloning work!")
        elif passed:
            feedback_parts.append("✅ Good cloning detected!")
        else:
            feedback_parts.append("❌ Cloning task needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in clone duplicate verification: {e}")
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
    result = check_clone_duplicate([], {}, {})
    print(f"Test result: {result}")