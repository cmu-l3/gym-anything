#!/usr/bin/env python3
"""
Verifier for GIMP crop to selection task.
Checks if image was cropped using selection-based cropping with meaningful size reduction.
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


def check_dimension_changes(original_img, result_img):
    """Check if the image dimensions were meaningfully reduced."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    # Calculate reduction percentages
    width_reduction = (orig_w - result_w) / orig_w if orig_w > 0 else 0
    height_reduction = (orig_h - result_h) / orig_h if orig_h > 0 else 0
    area_reduction = 1 - (result_w * result_h) / (orig_w * orig_h) if (orig_w * orig_h) > 0 else 0
    
    # Check criteria
    significantly_cropped = area_reduction >= 0.15  # At least 15% area removed
    not_too_aggressive = area_reduction <= 0.85    # At most 85% removed
    reasonable_size = result_w >= 100 and result_h >= 100  # Reasonable final size
    actually_changed = width_reduction > 0.05 or height_reduction > 0.05  # Actually cropped
    
    return {
        'width_reduction': width_reduction,
        'height_reduction': height_reduction,
        'area_reduction': area_reduction,
        'significantly_cropped': significantly_cropped,
        'not_too_aggressive': not_too_aggressive,
        'reasonable_size': reasonable_size,
        'actually_changed': actually_changed
    }


def extract_center_region(img, fraction):
    """Extract center region of image for content comparison."""
    w, h = img.size
    crop_w, crop_h = int(w * fraction), int(h * fraction)
    left = (w - crop_w) // 2
    top = (h - crop_h) // 2
    return img.crop((left, top, left + crop_w, top + crop_h))


def analyze_content_preservation(original_img, result_img):
    """Analyze if the important central content was preserved."""
    try:
        # Extract center regions for comparison
        orig_center = extract_center_region(original_img, 0.6)  # 60% of original
        
        # For result, use larger fraction since it's already cropped
        result_center = extract_center_region(result_img, 0.8)  # 80% of result
        
        # Resize for comparison if needed
        if orig_center.size != result_center.size:
            target_size = min(orig_center.size[0], result_center.size[0]), min(orig_center.size[1], result_center.size[1])
            if target_size[0] > 0 and target_size[1] > 0:
                orig_center = orig_center.resize(target_size)
                result_center = result_center.resize(target_size)
            else:
                return {'content_preserved': False, 'similarity': 0}
        
        # Convert to arrays and calculate similarity
        orig_array = np.array(orig_center.convert('RGB'))
        result_array = np.array(result_center.convert('RGB'))
        
        # Calculate normalized cross-correlation as similarity measure
        if orig_array.size > 0 and result_array.size > 0:
            # Flatten and normalize
            orig_flat = orig_array.flatten().astype(np.float32)
            result_flat = result_array.flatten().astype(np.float32)
            
            # Calculate correlation coefficient
            if np.std(orig_flat) > 0 and np.std(result_flat) > 0:
                correlation = np.corrcoef(orig_flat, result_flat)[0, 1]
                # Handle NaN case
                if np.isnan(correlation):
                    correlation = 0.0
            else:
                correlation = 0.0
            
            # Convert to similarity (0-1 range)
            similarity = max(0, correlation)
        else:
            similarity = 0.0
        
        content_preserved = similarity > 0.7
        
        return {
            'content_preserved': content_preserved,
            'similarity': similarity
        }
    except Exception as e:
        logging.error(f"Error in content analysis: {e}")
        return {'content_preserved': False, 'similarity': 0}


def check_crop_to_selection(traj, env_info, task_info):
    """
    Main verifier function for crop to selection task.
    Checks:
    1. Image dimensions were meaningfully reduced (cropped)
    2. Final size is reasonable (not too small)
    3. Important central content was preserved
    4. Image was actually modified
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
        "/home/ga/Desktop/cropped_selection.jpg",
        "/home/ga/Desktop/cropped_selection.png", 
        "/home/ga/Desktop/cropped_selection.jpeg",
        "/home/ga/Desktop/wide_landscape_cropped.jpg",
        "/home/ga/Desktop/landscape_cropped.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/wide_landscape.jpg",
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
        
        # Analyze dimension changes
        dimension_analysis = check_dimension_changes(original_image, result_image)
        
        # Analyze content preservation
        content_analysis = analyze_content_preservation(original_image, result_image)
        
        # Check if image was modified
        images_different = (original_image.size != result_image.size or 
                          not np.array_equal(np.array(original_image), 
                                           np.array(result_image.convert(original_image.mode))))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Area reduction: {dimension_analysis['area_reduction']:.1%}")
        feedback_parts.append(f"Content similarity: {content_analysis['similarity']:.2f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significantly cropped
        if dimension_analysis['significantly_cropped']:
            criteria_met += 1
        feedback_parts.append(f"Significantly cropped (≥15%): {'✅' if dimension_analysis['significantly_cropped'] else '❌'}")
        
        # 2. Reasonable final size
        if dimension_analysis['reasonable_size']:
            criteria_met += 1
        feedback_parts.append(f"Reasonable size (≥100x100): {'✅' if dimension_analysis['reasonable_size'] else '❌'}")
        
        # 3. Content preserved
        if content_analysis['content_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Content preserved (similarity>0.7): {'✅' if content_analysis['content_preserved'] else '❌'}")
        
        # 4. Image actually changed
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        # Additional checks for edge cases
        if dimension_analysis['not_too_aggressive'] == False:
            feedback_parts.append("⚠️ Warning: Very aggressive crop (>85% removed)")
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent crop to selection!")
        elif passed:
            feedback_parts.append("✅ Good crop to selection!")
        else:
            feedback_parts.append("❌ Crop to selection needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in crop to selection verification: {e}")
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
    result = check_crop_to_selection([], {}, {})
    print(f"Test result: {result}")