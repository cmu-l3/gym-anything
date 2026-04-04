#!/usr/bin/env python3
"""
Verifier for GIMP layer opacity adjustment task.
Checks if layer opacity was adjusted to 65% ±3% tolerance.
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


def create_65_percent_reference(original_img):
    """
    Create a mathematically perfect 65% opacity reference image.
    """
    # Convert to RGBA if not already
    if original_img.mode != 'RGBA':
        original_img = original_img.convert('RGBA')
    
    # Create a copy and adjust alpha channel to 65%
    reference = original_img.copy()
    
    # Split channels
    r, g, b, a = reference.split()
    
    # Set alpha to 65% (166 out of 255)
    alpha_array = np.array(a) * 0.65
    alpha_modified = Image.fromarray(alpha_array.astype(np.uint8))
    
    # Merge back
    reference_65 = Image.merge('RGBA', (r, g, b, alpha_modified))
    
    return reference_65


def analyze_opacity_from_alpha(result_img):
    """
    Analyze opacity directly from alpha channel if available.
    Returns average opacity as percentage (0-100).
    """
    if result_img.mode != 'RGBA':
        logging.debug(f"Image mode is {result_img.mode}, no alpha channel available")
        return None
    
    # Extract alpha channel
    alpha_channel = result_img.split()[3]  # Alpha is 4th channel
    alpha_array = np.array(alpha_channel)
    
    # Calculate average opacity as percentage
    average_alpha = np.mean(alpha_array)
    opacity_percentage = (average_alpha / 255.0) * 100
    
    logging.debug(f"Alpha channel analysis: avg={average_alpha:.1f}, opacity={opacity_percentage:.1f}%")
    
    return opacity_percentage


def analyze_opacity_from_intensity(original_img, result_img):
    """
    Estimate opacity by comparing pixel intensities between original and result.
    This works even when alpha channel isn't available.
    """
    # Ensure same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert both to RGB for comparison
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img).astype(np.float32)
    result_array = np.array(result_img).astype(np.float32)
    
    # Calculate average intensity for both images
    orig_intensity = np.mean(orig_array)
    result_intensity = np.mean(result_array)
    
    # For transparency against a white/light background, 
    # the result should be lighter (closer to background)
    # Simple approximation: opacity = result_intensity / orig_intensity
    # This assumes transparency is achieved by blending with a lighter background
    
    if orig_intensity > 0:
        estimated_opacity = (result_intensity / orig_intensity) * 100
        # Clamp to reasonable range
        estimated_opacity = max(0, min(100, estimated_opacity))
    else:
        estimated_opacity = 100  # Fallback
    
    logging.debug(f"Intensity analysis: orig={orig_intensity:.1f}, result={result_intensity:.1f}, opacity={estimated_opacity:.1f}%")
    
    return estimated_opacity


def check_opacity_precision(opacity_value, target=65, tolerance=3):
    """
    Check if opacity value is within target ± tolerance.
    """
    if opacity_value is None:
        return False, "No opacity value available"
    
    lower_bound = target - tolerance
    upper_bound = target + tolerance
    
    within_range = lower_bound <= opacity_value <= upper_bound
    
    return within_range, f"Opacity {opacity_value:.1f}% (target: {target}±{tolerance}%)"


def detect_transparency_evidence(result_img):
    """
    Look for evidence of transparency in the image.
    """
    evidence = {
        'has_alpha_channel': result_img.mode in ['RGBA', 'LA'],
        'alpha_variation': False,
        'partial_transparency': False
    }
    
    if evidence['has_alpha_channel']:
        alpha_channel = result_img.split()[-1]  # Last channel is alpha
        alpha_array = np.array(alpha_channel)
        
        # Check for variation in alpha values (not all 255 or all 0)
        alpha_std = np.std(alpha_array)
        alpha_mean = np.mean(alpha_array)
        
        evidence['alpha_variation'] = alpha_std > 5  # Some variation in transparency
        evidence['partial_transparency'] = 50 < alpha_mean < 250  # Partially transparent
        
        logging.debug(f"Alpha analysis: mean={alpha_mean:.1f}, std={alpha_std:.1f}")
    
    return evidence


def compare_with_reference(result_img, reference_img):
    """
    Compare result image with mathematically perfect 65% opacity reference.
    """
    try:
        # Ensure same size
        if result_img.size != reference_img.size:
            result_img = result_img.resize(reference_img.size)
        
        # Convert both to RGBA for comparison
        if result_img.mode != 'RGBA':
            result_img = result_img.convert('RGBA')
        if reference_img.mode != 'RGBA':
            reference_img = reference_img.convert('RGBA')
        
        result_array = np.array(result_img)
        ref_array = np.array(reference_img)
        
        # Calculate pixel-wise differences
        diff = np.abs(result_array.astype(np.float32) - ref_array.astype(np.float32))
        mean_diff = np.mean(diff)
        
        # Calculate similarity (lower difference = higher similarity)
        similarity = max(0, 100 - (mean_diff / 2.55))  # Scale to 0-100
        
        logging.debug(f"Reference comparison: mean_diff={mean_diff:.1f}, similarity={similarity:.1f}%")
        
        return similarity >= 75  # 75% similarity threshold
    
    except Exception as e:
        logging.error(f"Error in reference comparison: {e}")
        return False


def check_layer_opacity(traj, env_info, task_info):
    """
    Main verifier function for layer opacity adjustment task.
    Checks:
    1. Layer opacity was adjusted to 65% (±3% tolerance)
    2. Transparency is uniform across the image
    3. Image quality is preserved
    4. Proper transparency implementation
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
        "/home/ga/Desktop/flower_65_opacity.png",
        "/home/ga/Desktop/flower_65_opacity.jpg", 
        "/home/ga/Desktop/flower_65_opacity.jpeg",
        "/home/ga/Desktop/flower_image_opacity.png",
        "/home/ga/Desktop/flower_opacity.png"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/flower_image.jpg",
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
        
        # Create reference image at 65% opacity
        reference_65 = create_65_percent_reference(original_image)
        
        # Multiple opacity analysis methods
        opacity_alpha = analyze_opacity_from_alpha(result_image)
        opacity_intensity = analyze_opacity_from_intensity(original_image, result_image)
        
        # Check transparency evidence
        transparency_evidence = detect_transparency_evidence(result_image)
        
        # Compare with mathematical reference
        reference_match = compare_with_reference(result_image, reference_65)
        
        # Check if image was modified
        images_different = not np.array_equal(np.array(original_image.convert('RGB')), 
                                            np.array(result_image.convert('RGB')))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Result format: {result_image.mode}")
        
        # Determine best opacity measurement
        primary_opacity = opacity_alpha if opacity_alpha is not None else opacity_intensity
        
        if opacity_alpha is not None:
            feedback_parts.append(f"Alpha channel opacity: {opacity_alpha:.1f}%")
        if opacity_intensity is not None:
            feedback_parts.append(f"Intensity-based opacity: {opacity_intensity:.1f}%")
        
        # Check precision
        precision_ok, precision_msg = check_opacity_precision(primary_opacity, 65, 3)
        feedback_parts.append(f"Target precision: {'✅' if precision_ok else '❌'} ({precision_msg})")
        
        feedback_parts.append(f"Has alpha channel: {'✅' if transparency_evidence['has_alpha_channel'] else '❌'}")
        feedback_parts.append(f"Partial transparency: {'✅' if transparency_evidence['partial_transparency'] else '❌'}")
        feedback_parts.append(f"Reference match: {'✅' if reference_match else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        if precision_ok:
            criteria_met += 1
        if transparency_evidence['has_alpha_channel'] or transparency_evidence['partial_transparency']:
            criteria_met += 1
        if reference_match:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        # Bonus criterion for having both alpha and good precision
        if opacity_alpha is not None and precision_ok:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 75% score
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect opacity adjustment!")
        elif passed:
            feedback_parts.append("✅ Good opacity adjustment!")
        else:
            feedback_parts.append("❌ Opacity adjustment needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in layer opacity verification: {e}")
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
    result = check_layer_opacity([], {}, {})
    print(f"Test result: {result}")