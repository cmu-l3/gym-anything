#!/usr/bin/env python3
"""
Verifier for GIMP oil painting effect task.
Checks if the oilify filter was successfully applied to create an oil painting effect.
"""

import logging
from pathlib import Path
from PIL import Image, ImageFilter
import numpy as np
import sys
import os

# Add the tasks directory to path so we can import verification_utils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + "/..")
from verification_utils import setup_verification_environment, cleanup_verification_environment

logging.basicConfig(level=logging.DEBUG)

try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    try:
        from skimage.measure import compare_ssim as ssim
    except ImportError:
        ssim = None
        logging.warning("SSIM not available, using fallback similarity measure")


def measure_edge_reduction(original_img, result_img):
    """
    Measure reduction in sharp edges after oil painting effect.
    Oil painting should significantly reduce high-frequency detail.
    """
    # Apply edge detection to both images
    orig_edges = original_img.convert('L').filter(ImageFilter.FIND_EDGES)
    result_edges = result_img.convert('L').filter(ImageFilter.FIND_EDGES)
    
    # Count strong edge pixels (above threshold)
    orig_edge_array = np.array(orig_edges)
    result_edge_array = np.array(result_edges)
    
    orig_strong_edges = np.sum(orig_edge_array > 50)
    result_strong_edges = np.sum(result_edge_array > 50)
    
    # Calculate reduction percentage
    if orig_strong_edges > 0:
        reduction = (orig_strong_edges - result_strong_edges) / orig_strong_edges
    else:
        reduction = 0
    
    return {
        'original_edges': orig_strong_edges,
        'result_edges': result_strong_edges,
        'reduction_ratio': reduction,
        'significant_reduction': reduction >= 0.4  # At least 40% reduction
    }


def measure_local_uniformity(original_img, result_img, window_size=7):
    """
    Measure increase in local color uniformity (brush stroke effect).
    Oil painting creates regions of more uniform color.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    def local_variance(img_array):
        """Calculate local variance using sliding window approach."""
        try:
            from scipy.ndimage import uniform_filter
            # Calculate local mean and mean of squares using uniform filter
            mean = uniform_filter(img_array, size=(window_size, window_size, 1))
            mean_sq = uniform_filter(img_array**2, size=(window_size, window_size, 1))
            variance = mean_sq - mean**2
            return np.mean(variance)
        except ImportError:
            # Fallback: simple sliding window variance calculation
            h, w, c = img_array.shape
            total_variance = 0
            count = 0
            step = max(1, window_size // 2)  # Reduce computation
            
            for y in range(0, h - window_size, step):
                for x in range(0, w - window_size, step):
                    window = img_array[y:y+window_size, x:x+window_size]
                    total_variance += np.var(window)
                    count += 1
            
            return total_variance / count if count > 0 else 0
    
    orig_variance = local_variance(orig_array)
    result_variance = local_variance(result_array)
    
    # Calculate variance reduction
    if orig_variance > 0:
        reduction = (orig_variance - result_variance) / orig_variance
    else:
        reduction = 0
    
    return {
        'original_variance': orig_variance,
        'result_variance': result_variance,
        'variance_reduction': reduction,
        'significant_uniformity': reduction >= 0.3  # At least 30% variance reduction
    }


def check_structural_preservation(original_img, result_img):
    """
    Verify image is transformed but still recognizable.
    SSIM should be in the range 0.6-0.85 for good oil painting effect.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    if ssim is not None:
        try:
            orig_gray = np.array(original_img.convert('L'))
            result_gray = np.array(result_img.convert('L'))
            
            # Calculate SSIM
            similarity = ssim(orig_gray, result_gray, win_size=7)
            
            return {
                'ssim_score': similarity,
                'well_preserved': 0.6 <= similarity <= 0.85
            }
        except Exception as e:
            logging.warning(f"SSIM calculation failed: {e}")
    
    # Fallback: simple correlation-based similarity
    orig_array = np.array(original_img.convert('L')).flatten()
    result_array = np.array(result_img.convert('L')).flatten()
    
    correlation = np.corrcoef(orig_array, result_array)[0, 1]
    
    return {
        'ssim_score': correlation,
        'well_preserved': 0.6 <= correlation <= 0.9
    }


def measure_pixel_changes(original_img, result_img, threshold=20):
    """
    Measure percentage of significantly changed pixels.
    Oil painting should modify a substantial portion of the image.
    """
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    orig_array = np.array(original_img.convert('RGB')).astype(np.float32)
    result_array = np.array(result_img.convert('RGB')).astype(np.float32)
    
    # Calculate per-pixel difference magnitude
    diff = np.abs(orig_array - result_array)
    magnitude = np.sqrt(np.sum(diff**2, axis=2))
    
    # Count significantly changed pixels
    changed_pixels = np.sum(magnitude > threshold)
    total_pixels = magnitude.size
    change_percentage = changed_pixels / total_pixels
    
    return {
        'mean_change': np.mean(magnitude),
        'change_percentage': change_percentage,
        'substantial_change': change_percentage >= 0.3  # At least 30% of pixels changed
    }


def check_oil_painting_effect(traj, env_info, task_info):
    """
    Main verifier function for oil painting effect task.
    Checks:
    1. Sharp edges were significantly reduced (softening effect)
    2. Local color variance decreased (brush stroke uniformity)
    3. Image structure is preserved but transformed
    4. Substantial pixel changes occurred
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
        "/home/ga/Desktop/oil_painting.jpg",
        "/home/ga/Desktop/oil_painting.png", 
        "/home/ga/Desktop/oil_painting.jpeg",
        "/home/ga/Desktop/photo_for_oilify_oil.jpg",
        "/home/ga/Desktop/oilified.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/photo_for_oilify.jpg",
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
        
        # Perform oil painting effect analysis
        edge_analysis = measure_edge_reduction(original_image, result_image)
        uniformity_analysis = measure_local_uniformity(original_image, result_image)
        preservation_analysis = check_structural_preservation(original_image, result_image)
        change_analysis = measure_pixel_changes(original_image, result_image)
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge reduction: {edge_analysis['reduction_ratio']:.2f}")
        feedback_parts.append(f"Variance reduction: {uniformity_analysis['variance_reduction']:.2f}")
        feedback_parts.append(f"SSIM/similarity: {preservation_analysis['ssim_score']:.3f}")
        feedback_parts.append(f"Pixels changed: {change_analysis['change_percentage']:.1%}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Significant edge reduction (oil painting softens edges)
        if edge_analysis['significant_reduction']:
            criteria_met += 1
        feedback_parts.append(f"Edges softened: {'✅' if edge_analysis['significant_reduction'] else '❌'}")
        
        # 2. Local color uniformity increased (brush stroke effect)
        if uniformity_analysis['significant_uniformity']:
            criteria_met += 1
        feedback_parts.append(f"Color uniformity increased: {'✅' if uniformity_analysis['significant_uniformity'] else '❌'}")
        
        # 3. Structure preserved (recognizable but transformed)
        if preservation_analysis['well_preserved']:
            criteria_met += 1
        feedback_parts.append(f"Structure preserved: {'✅' if preservation_analysis['well_preserved'] else '❌'}")
        
        # 4. Substantial modification occurred
        if change_analysis['substantial_change']:
            criteria_met += 1
        feedback_parts.append(f"Substantially modified: {'✅' if change_analysis['substantial_change'] else '❌'}")
        
        # Calculate success based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect oil painting effect!")
        elif passed:
            feedback_parts.append("✅ Good oil painting effect!")
        else:
            feedback_parts.append("❌ Oil painting effect needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in oil painting effect verification: {e}")
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
    result = check_oil_painting_effect([], {}, {})
    print(f"Test result: {result}")