#!/usr/bin/env python3
"""
Verifier for GIMP 90° counter-clockwise rotation task.
Checks if image was rotated exactly 90° counter-clockwise.
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

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
        HAS_SSIM = True
    except ImportError:
        HAS_SSIM = False
        logging.warning("scikit-image not available, using basic pixel comparison")


def verify_90_ccw_rotation(original_img, result_img):
    """
    Verify that result_img is a perfect 90° counter-clockwise rotation of original_img.
    Returns detailed analysis including direction correctness.
    """
    # Generate reference rotations
    reference_ccw = original_img.rotate(90, expand=True)  # 90° CCW
    reference_cw = original_img.rotate(-90, expand=True)  # 90° CW for comparison
    reference_180 = original_img.rotate(180, expand=True)  # 180° for comparison
    
    # Check dimensions - after 90° rotation, width and height should be swapped
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    ref_w, ref_h = reference_ccw.size
    
    dimensions_swapped = (orig_w == result_h) and (orig_h == result_w)
    dimensions_match_ref = (result_w == ref_w) and (result_h == ref_h)
    
    logging.debug(f"Original: {orig_w}x{orig_h}")
    logging.debug(f"Result: {result_w}x{result_h}")
    logging.debug(f"Reference CCW: {ref_w}x{ref_h}")
    logging.debug(f"Dimensions swapped: {dimensions_swapped}")
    logging.debug(f"Dimensions match reference: {dimensions_match_ref}")
    
    analysis = {
        'dimensions_swapped': dimensions_swapped,
        'dimensions_match_ref': dimensions_match_ref,
        'original_size': (orig_w, orig_h),
        'result_size': (result_w, result_h),
        'reference_size': (ref_w, ref_h)
    }
    
    if not dimensions_match_ref:
        analysis['ssim_ccw'] = 0.0
        analysis['ssim_cw'] = 0.0
        analysis['ssim_180'] = 0.0
        analysis['correct_direction'] = False
        analysis['rotation_detected'] = False
        return analysis
    
    # Use SSIM if available, otherwise fall back to pixel comparison
    if HAS_SSIM:
        try:
            # Convert images to RGB and ensure same size
            ref_ccw_rgb = reference_ccw.convert('RGB')
            ref_cw_rgb = reference_cw.convert('RGB')
            ref_180_rgb = reference_180.convert('RGB')
            result_rgb = result_img.convert('RGB')
            
            # Calculate SSIM scores
            ref_ccw_array = np.array(ref_ccw_rgb)
            ref_cw_array = np.array(ref_cw_rgb)
            ref_180_array = np.array(ref_180_rgb)
            result_array = np.array(result_rgb)
            
            # Determine appropriate window size for SSIM
            min_dim = min(result_array.shape[0], result_array.shape[1])
            win_size = min(7, min_dim if min_dim % 2 == 1 else min_dim - 1)
            win_size = max(3, win_size)  # Minimum window size of 3
            
            try:
                # Try newer SSIM API first
                ssim_ccw = ssim(ref_ccw_array, result_array, win_size=win_size, channel_axis=2)
                ssim_cw = ssim(ref_cw_array, result_array, win_size=win_size, channel_axis=2)
                ssim_180 = ssim(ref_180_array, result_array, win_size=win_size, channel_axis=2)
            except TypeError:
                # Fall back to older SSIM API
                ssim_ccw = ssim(ref_ccw_array, result_array, win_size=win_size, multichannel=True)
                ssim_cw = ssim(ref_cw_array, result_array, win_size=win_size, multichannel=True)
                ssim_180 = ssim(ref_180_array, result_array, win_size=win_size, multichannel=True)
            
            analysis.update({
                'ssim_ccw': ssim_ccw,
                'ssim_cw': ssim_cw,
                'ssim_180': ssim_180,
                'correct_direction': ssim_ccw > max(ssim_cw, ssim_180),
                'rotation_detected': max(ssim_ccw, ssim_cw, ssim_180) > 0.8
            })
            
            logging.debug(f"SSIM CCW: {ssim_ccw:.3f}")
            logging.debug(f"SSIM CW: {ssim_cw:.3f}")
            logging.debug(f"SSIM 180: {ssim_180:.3f}")
            
        except Exception as e:
            logging.error(f"SSIM calculation failed: {e}")
            # Fall back to basic comparison
            analysis.update({
                'ssim_ccw': 0.0,
                'ssim_cw': 0.0,
                'ssim_180': 0.0,
                'correct_direction': False,
                'rotation_detected': False
            })
    else:
        # Basic pixel comparison fallback
        ref_ccw_array = np.array(reference_ccw.convert('RGB'))
        result_array = np.array(result_img.convert('RGB'))
        
        if ref_ccw_array.shape == result_array.shape:
            pixel_diff = np.mean(np.abs(ref_ccw_array.astype(np.float32) - result_array.astype(np.float32)))
            ssim_ccw = max(0, 1 - pixel_diff / 255.0)  # Normalize to 0-1 range
        else:
            ssim_ccw = 0.0
        
        analysis.update({
            'ssim_ccw': ssim_ccw,
            'ssim_cw': 0.0,
            'ssim_180': 0.0,
            'correct_direction': ssim_ccw > 0.8,
            'rotation_detected': ssim_ccw > 0.5
        })
    
    return analysis


def check_rotation_ccw(traj, env_info, task_info):
    """
    Main verifier function for 90° counter-clockwise rotation task.
    Checks:
    1. Image was rotated exactly 90° counter-clockwise
    2. Dimensions were properly swapped (width ↔ height)
    3. Rotation direction is correct (not clockwise or 180°)
    4. High structural similarity with reference rotation
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
        "/home/ga/Desktop/rotated_ccw.jpg",
        "/home/ga/Desktop/rotated_ccw.png", 
        "/home/ga/Desktop/rotated_ccw.jpeg",
        "/home/ga/Desktop/rotate_test_image_rotated.jpg",
        "/home/ga/Desktop/rotate_test_rotated.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/rotate_test_image.jpg",
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
        
        # Verify 90° CCW rotation
        rotation_analysis = verify_90_ccw_rotation(original_image, result_image)
        
        # Check if image was modified from original
        images_different = not np.array_equal(np.array(original_image), np.array(result_image.convert(original_image.mode)))
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {rotation_analysis['original_size']}")
        feedback_parts.append(f"Result size: {rotation_analysis['result_size']}")
        feedback_parts.append(f"Reference CCW size: {rotation_analysis['reference_size']}")
        feedback_parts.append(f"Dimensions swapped: {'✅' if rotation_analysis['dimensions_swapped'] else '❌'}")
        feedback_parts.append(f"SSIM CCW: {rotation_analysis['ssim_ccw']:.3f}")
        feedback_parts.append(f"SSIM CW: {rotation_analysis['ssim_cw']:.3f}")
        feedback_parts.append(f"Correct direction (CCW): {'✅' if rotation_analysis['correct_direction'] else '❌'}")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Perfect or near-perfect CCW match (SSIM ≥ 0.95)
        perfect_ccw_match = rotation_analysis['ssim_ccw'] >= 0.95
        if perfect_ccw_match:
            criteria_met += 1
        
        # 2. Dimensions properly swapped
        if rotation_analysis['dimensions_swapped']:
            criteria_met += 1
        
        # 3. Correct rotation direction (CCW, not CW or 180°)
        if rotation_analysis['correct_direction']:
            criteria_met += 1
        
        # 4. Quality maintained (dimensions match reference)
        if rotation_analysis['dimensions_match_ref']:
            criteria_met += 1
        
        # 5. Image was actually modified
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (80%)
        
        # Special handling for wrong direction
        if rotation_analysis['ssim_cw'] > rotation_analysis['ssim_ccw'] and rotation_analysis['ssim_cw'] > 0.8:
            feedback_parts.append("❌ WRONG DIRECTION: Image was rotated clockwise instead of counter-clockwise!")
            score = max(score, 25)  # Give some credit for rotation, but not passing
            passed = False
        elif rotation_analysis['ssim_180'] > rotation_analysis['ssim_ccw'] and rotation_analysis['ssim_180'] > 0.8:
            feedback_parts.append("❌ WRONG ANGLE: Image was rotated 180° instead of 90° counter-clockwise!")
            score = max(score, 25)
            passed = False
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect 90° counter-clockwise rotation!")
        elif passed:
            feedback_parts.append("✅ Good 90° counter-clockwise rotation!")
        else:
            feedback_parts.append("❌ 90° counter-clockwise rotation failed or incorrect")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in rotation verification: {e}")
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
    result = check_rotation_ccw([], {}, {})
    print(f"Test result: {result}")