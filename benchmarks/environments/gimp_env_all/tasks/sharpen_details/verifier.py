#!/usr/bin/env python3
"""
Verifier for GIMP sharpen details task.
Checks if image was sharpened using edge enhancement and frequency analysis.
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


def analyze_edge_enhancement(original_img, result_img):
    """
    Analyze edge enhancement using Sobel edge detection.
    Returns edge intensity metrics and enhancement ratio.
    """
    # Convert to grayscale for edge analysis
    if original_img.mode != 'L':
        orig_gray = np.array(original_img.convert('L'))
    else:
        orig_gray = np.array(original_img)
    
    if result_img.mode != 'L':
        result_gray = np.array(result_img.convert('L'))
    else:
        result_gray = np.array(result_img)
    
    # Ensure same size
    if orig_gray.shape != result_gray.shape:
        from PIL import Image as PILImage
        result_pil = PILImage.fromarray(result_gray)
        result_pil = result_pil.resize((orig_gray.shape[1], orig_gray.shape[0]))
        result_gray = np.array(result_pil)
    
    def calculate_edge_intensity(img_array):
        """Calculate edge intensity using Sobel operators."""
        try:
            from scipy.ndimage import sobel
            # Apply Sobel operators
            sobel_x = sobel(img_array, axis=1)
            sobel_y = sobel(img_array, axis=0)
            # Calculate magnitude
            magnitude = np.hypot(sobel_x, sobel_y)
            return np.mean(magnitude)
        except ImportError:
            # Fallback: simple gradient approximation
            grad_x = np.abs(np.diff(img_array, axis=1))
            grad_y = np.abs(np.diff(img_array, axis=0))
            # Pad to match original size
            grad_x = np.pad(grad_x, ((0, 0), (0, 1)), mode='edge')
            grad_y = np.pad(grad_y, ((0, 1), (0, 0)), mode='edge')
            magnitude = np.sqrt(grad_x**2 + grad_y**2)
            return np.mean(magnitude)
    
    orig_edge_intensity = calculate_edge_intensity(orig_gray)
    result_edge_intensity = calculate_edge_intensity(result_gray)
    
    enhancement_ratio = result_edge_intensity / (orig_edge_intensity + 1e-6)
    
    return {
        'original_edge_intensity': orig_edge_intensity,
        'result_edge_intensity': result_edge_intensity,
        'enhancement_ratio': enhancement_ratio,
        'edges_enhanced': 1.15 <= enhancement_ratio <= 1.40
    }


def analyze_detail_enhancement(original_img, result_img):
    """
    Analyze high-frequency content and detail enhancement.
    Uses local standard deviation as a proxy for detail content.
    """
    # Convert to grayscale
    if original_img.mode != 'L':
        orig_gray = np.array(original_img.convert('L'))
    else:
        orig_gray = np.array(original_img)
    
    if result_img.mode != 'L':
        result_gray = np.array(result_img.convert('L'))
    else:
        result_gray = np.array(result_img)
    
    # Ensure same size
    if orig_gray.shape != result_gray.shape:
        from PIL import Image as PILImage
        result_pil = PILImage.fromarray(result_gray)
        result_pil = result_pil.resize((orig_gray.shape[1], orig_gray.shape[0]))
        result_gray = np.array(result_pil)
    
    def local_detail_measure(img_array, window_size=5):
        """Calculate local standard deviation as detail measure."""
        try:
            from scipy.ndimage import generic_filter
            return np.mean(generic_filter(img_array.astype(float), np.std, size=window_size))
        except ImportError:
            # Fallback: simple variance measure
            return np.std(img_array)
    
    orig_detail = local_detail_measure(orig_gray)
    result_detail = local_detail_measure(result_gray)
    
    detail_increase = (result_detail - orig_detail) / (orig_detail + 1e-6)
    
    return {
        'original_detail': orig_detail,
        'result_detail': result_detail,
        'detail_increase': detail_increase,
        'details_improved': detail_increase > 0.05  # At least 5% increase
    }


def check_structural_similarity(original_img, result_img):
    """
    Check if overall image structure is preserved using SSIM.
    """
    try:
        from skimage.metrics import structural_similarity as ssim
        
        # Convert to same format and size
        if original_img.mode != 'RGB':
            original_rgb = original_img.convert('RGB')
        else:
            original_rgb = original_img
            
        if result_img.mode != 'RGB':
            result_rgb = result_img.convert('RGB')
        else:
            result_rgb = result_img
        
        if original_rgb.size != result_rgb.size:
            result_rgb = result_rgb.resize(original_rgb.size)
        
        orig_array = np.array(original_rgb)
        result_array = np.array(result_rgb)
        
        # Calculate SSIM
        try:
            # Try newer version with channel_axis
            ssim_score = ssim(orig_array, result_array, channel_axis=2)
        except TypeError:
            # Fallback to older version with multichannel
            ssim_score = ssim(orig_array, result_array, multichannel=True)
        
        return {
            'ssim_score': ssim_score,
            'structure_preserved': ssim_score >= 0.85
        }
        
    except ImportError:
        # Fallback: simple pixel correlation
        if original_img.size != result_img.size:
            result_img = result_img.resize(original_img.size)
        
        orig_array = np.array(original_img.convert('L'))
        result_array = np.array(result_img.convert('L'))
        
        correlation = np.corrcoef(orig_array.flatten(), result_array.flatten())[0,1]
        
        return {
            'ssim_score': correlation,
            'structure_preserved': correlation >= 0.80
        }


def check_meaningful_change(original_img, result_img):
    """Check if the image was meaningfully modified."""
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Convert to same format
    orig_array = np.array(original_img.convert('RGB'))
    result_array = np.array(result_img.convert('RGB'))
    
    # Calculate pixel-wise differences
    diff = np.abs(orig_array.astype(np.float32) - result_array.astype(np.float32))
    
    # Calculate percentage of significantly changed pixels
    significant_change = np.sqrt(np.sum(diff ** 2, axis=2)) > 15  # Pixels with >15 intensity change
    change_percentage = (np.sum(significant_change) / significant_change.size) * 100
    
    return {
        'change_percentage': change_percentage,
        'meaningfully_changed': change_percentage > 2  # At least 2% of pixels changed
    }


def check_image_sharpening(traj, env_info, task_info):
    """
    Main verifier function for sharpen details task.
    Checks:
    1. Edge intensity was enhanced (15-40% increase)
    2. High-frequency/detail content increased
    3. Overall structure was preserved (SSIM ≥ 0.85)
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
        "/home/ga/Desktop/sharpened_image.jpg",
        "/home/ga/Desktop/sharpened_image.png",
        "/home/ga/Desktop/sharpened_image.jpeg",
        "/home/ga/Desktop/soft_image_sharpened.jpg",
        "/home/ga/Desktop/enhanced_image.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/soft_image.jpg",
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
        
        # Analyze edge enhancement
        edge_analysis = analyze_edge_enhancement(original_image, result_image)
        
        # Analyze detail enhancement
        detail_analysis = analyze_detail_enhancement(original_image, result_image)
        
        # Check structural similarity
        structure_analysis = check_structural_similarity(original_image, result_image)
        
        # Check meaningful change
        change_analysis = check_meaningful_change(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge enhancement ratio: {edge_analysis['enhancement_ratio']:.3f}")
        feedback_parts.append(f"Detail increase: {detail_analysis['detail_increase']:.1%}")
        feedback_parts.append(f"SSIM score: {structure_analysis['ssim_score']:.3f}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1f}%")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 5
        
        # 1. Edges enhanced (15-40% increase)
        if edge_analysis['edges_enhanced']:
            criteria_met += 1
        feedback_parts.append(f"Edges enhanced: {'✅' if edge_analysis['edges_enhanced'] else '❌'}")
        
        # 2. Details improved
        if detail_analysis['details_improved']:
            criteria_met += 1
        feedback_parts.append(f"Details improved: {'✅' if detail_analysis['details_improved'] else '❌'}")
        
        # 3. Structure preserved
        if structure_analysis['structure_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Structure preserved: {'✅' if structure_analysis['structure_preserved'] else '❌'}")
        
        # 4. Quality maintained (not over-sharpened)
        not_over_sharpened = edge_analysis['enhancement_ratio'] < 1.60  # Not too much enhancement
        if not_over_sharpened:
            criteria_met += 1
        feedback_parts.append(f"Quality maintained: {'✅' if not_over_sharpened else '❌'}")
        
        # 5. Image modified
        if change_analysis['meaningfully_changed']:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if change_analysis['meaningfully_changed'] else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent image sharpening!")
        elif passed:
            feedback_parts.append("✅ Good image sharpening!")
        else:
            feedback_parts.append("❌ Image sharpening needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in sharpen details verification: {e}")
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
    result = check_image_sharpening([], {}, {})
    print(f"Test result: {result}")