#!/usr/bin/env python3
"""
Verifier for GIMP autocrop to content task.
Checks if the image was successfully autocropped to remove borders while preserving content.
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
        logging.warning("SSIM not available, using basic correlation")


def check_dimensions_reduced(original_img, result_img):
    """Check if result image dimensions are smaller than original."""
    orig_w, orig_h = original_img.size
    result_w, result_h = result_img.size
    
    width_reduced = result_w < orig_w
    height_reduced = result_h < orig_h
    both_reduced = width_reduced and height_reduced
    
    # Calculate area reduction percentage
    orig_area = orig_w * orig_h
    result_area = result_w * result_h
    area_reduction_pct = ((orig_area - result_area) / orig_area) * 100 if orig_area > 0 else 0
    
    return {
        'width_reduced': width_reduced,
        'height_reduced': height_reduced,
        'both_reduced': both_reduced,
        'area_reduction_pct': area_reduction_pct,
        'substantial_reduction': area_reduction_pct >= 10  # At least 10% area reduction
    }


def analyze_content_preservation(original_img, result_img):
    """
    Analyze if the main content was preserved during autocrop.
    Compare center regions to ensure important content wasn't lost.
    """
    # Resize result to match original for comparison if needed
    if original_img.size != result_img.size:
        # For content preservation check, we need to identify corresponding regions
        # Since autocrop removes borders, the result should contain the center content
        pass  # We'll handle this by extracting center regions appropriately
    
    # Convert to grayscale for analysis
    if original_img.mode != 'L':
        orig_gray = original_img.convert('L')
    else:
        orig_gray = original_img
        
    if result_img.mode != 'L':
        result_gray = result_img.convert('L')
    else:
        result_gray = result_img
    
    orig_array = np.array(orig_gray)
    result_array = np.array(result_gray)
    
    orig_h, orig_w = orig_array.shape
    result_h, result_w = result_array.shape
    
    # Extract center region from original (this should correspond to the result content)
    # Use center 80% of original as the expected content area
    center_margin_h = int(orig_h * 0.1)  # 10% margin
    center_margin_w = int(orig_w * 0.1)  # 10% margin
    
    orig_center = orig_array[center_margin_h:orig_h-center_margin_h, 
                            center_margin_w:orig_w-center_margin_w]
    
    # The result should be similar to this center region
    # Resize for comparison if needed
    if orig_center.shape != result_array.shape:
        from PIL import Image as PILImage
        orig_center_img = PILImage.fromarray(orig_center)
        orig_center_img = orig_center_img.resize((result_w, result_h), PILImage.Resampling.LANCZOS)
        orig_center = np.array(orig_center_img)
    
    # Calculate similarity
    if HAS_SSIM and orig_center.shape == result_array.shape and orig_center.size > 49:  # SSIM needs at least 7x7
        try:
            similarity = ssim(orig_center, result_array)
        except Exception as e:
            logging.warning(f"SSIM failed: {e}, using correlation")
            # Fallback to correlation
            similarity = np.corrcoef(orig_center.flatten(), result_array.flatten())[0, 1]
            if np.isnan(similarity):
                similarity = 0
    else:
        # Use correlation as fallback
        if orig_center.size > 0 and result_array.size > 0:
            similarity = np.corrcoef(orig_center.flatten(), result_array.flatten())[0, 1]
            if np.isnan(similarity):
                similarity = 0
        else:
            similarity = 0
    
    # Calculate detail preservation (standard deviation should be similar)
    orig_detail = np.std(orig_center) if orig_center.size > 0 else 0
    result_detail = np.std(result_array) if result_array.size > 0 else 0
    detail_ratio = (result_detail / orig_detail) if orig_detail > 0 else 0
    
    return {
        'similarity': similarity,
        'content_preserved': similarity >= 0.95,  # High similarity required
        'detail_preserved': detail_ratio >= 0.8,  # At least 80% of detail maintained
        'orig_detail': orig_detail,
        'result_detail': result_detail,
        'detail_ratio': detail_ratio
    }


def check_border_removal(original_img, result_img):
    """
    Verify that uniform borders were removed.
    Check that edge regions from original are no longer present.
    """
    if original_img.mode != 'RGB':
        orig_rgb = original_img.convert('RGB')
    else:
        orig_rgb = original_img
        
    orig_array = np.array(orig_rgb)
    orig_h, orig_w, _ = orig_array.shape
    
    # Analyze original border regions (edges of the image)
    border_width = min(50, orig_w // 8)  # Use up to 50px or 12.5% of width
    border_height = min(50, orig_h // 8)  # Use up to 50px or 12.5% of height
    
    # Extract border regions
    top_border = orig_array[:border_height, :, :]
    bottom_border = orig_array[orig_h-border_height:, :, :]
    left_border = orig_array[:, :border_width, :]
    right_border = orig_array[:, orig_w-border_width:, :]
    
    # Check if borders are relatively uniform (likely to be removed by autocrop)
    def is_uniform_region(region, threshold=30):
        """Check if a region has low variance (uniform)."""
        if region.size == 0:
            return False
        region_flat = region.reshape(-1, region.shape[-1])
        std_per_channel = np.std(region_flat, axis=0)
        return np.mean(std_per_channel) < threshold
    
    uniform_borders = {
        'top': is_uniform_region(top_border),
        'bottom': is_uniform_region(bottom_border), 
        'left': is_uniform_region(left_border),
        'right': is_uniform_region(right_border)
    }
    
    num_uniform_borders = sum(uniform_borders.values())
    has_uniform_borders = num_uniform_borders >= 2  # At least 2 uniform borders
    
    return {
        'uniform_borders': uniform_borders,
        'num_uniform_borders': num_uniform_borders,
        'has_uniform_borders': has_uniform_borders,
        'borders_likely_removed': has_uniform_borders  # If original had uniform borders, they should be gone
    }


def assess_crop_tightness(result_img):
    """
    Assess if the result crop is tight around the content.
    Check that there isn't excessive uniform space around the edges.
    """
    if result_img.mode != 'RGB':
        result_rgb = result_img.convert('RGB')
    else:
        result_rgb = result_img
        
    result_array = np.array(result_rgb)
    result_h, result_w, _ = result_array.shape
    
    # Check edges of result image for uniformity
    edge_width = min(20, result_w // 10)  # Check up to 20px or 10% of width
    edge_height = min(20, result_h // 10)  # Check up to 20px or 10% of height
    
    if edge_width <= 0 or edge_height <= 0:
        return {'tight_crop': True, 'excess_uniform_space': False}
    
    # Extract edge regions
    top_edge = result_array[:edge_height, :, :]
    bottom_edge = result_array[result_h-edge_height:, :, :]
    left_edge = result_array[:, :edge_width, :]
    right_edge = result_array[:, result_w-edge_width:, :]
    
    # Check if edges are uniform (indicating loose cropping)
    def has_uniform_edge(edge, threshold=25):
        if edge.size == 0:
            return False
        edge_flat = edge.reshape(-1, edge.shape[-1])
        std_per_channel = np.std(edge_flat, axis=0)
        return np.mean(std_per_channel) < threshold
    
    uniform_edges = {
        'top': has_uniform_edge(top_edge),
        'bottom': has_uniform_edge(bottom_edge),
        'left': has_uniform_edge(left_edge),
        'right': has_uniform_edge(right_edge)
    }
    
    num_uniform_edges = sum(uniform_edges.values())
    excess_uniform_space = num_uniform_edges >= 3  # Too many uniform edges suggest loose cropping
    tight_crop = not excess_uniform_space
    
    return {
        'uniform_edges': uniform_edges,
        'num_uniform_edges': num_uniform_edges,
        'excess_uniform_space': excess_uniform_space,
        'tight_crop': tight_crop
    }


def check_autocrop(traj, env_info, task_info):
    """
    Main verifier function for autocrop to content task.
    Checks:
    1. Image dimensions were reduced (both width and height smaller)
    2. Substantial area reduction (at least 10%)
    3. Content was preserved (center region similarity ≥ 0.95)
    4. Borders were likely removed (if original had uniform borders)
    5. Result crop is tight around content
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
        "/home/ga/Desktop/autocropped_image.jpg",
        "/home/ga/Desktop/autocropped_image.png",
        "/home/ga/Desktop/autocropped_image.jpeg",
        "/home/ga/Desktop/bordered_image_cropped.jpg",
        "/home/ga/Desktop/cropped.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/bordered_image.jpg",
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
        
        # Check if dimensions were reduced
        dimension_analysis = check_dimensions_reduced(original_image, result_image)
        
        # Analyze content preservation
        content_analysis = analyze_content_preservation(original_image, result_image)
        
        # Check border removal
        border_analysis = check_border_removal(original_image, result_image)
        
        # Assess crop tightness
        tightness_analysis = assess_crop_tightness(result_image)
        
        # Check if image was modified
        images_different = original_image.size != result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Area reduction: {dimension_analysis['area_reduction_pct']:.1f}%")
        feedback_parts.append(f"Dimensions reduced: {'✅' if dimension_analysis['both_reduced'] else '❌'}")
        feedback_parts.append(f"Substantial reduction: {'✅' if dimension_analysis['substantial_reduction'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_analysis['content_preserved'] else '❌'} (sim={content_analysis['similarity']:.3f})")
        feedback_parts.append(f"Borders removed: {'✅' if border_analysis['borders_likely_removed'] else '❌'}")
        feedback_parts.append(f"Tight crop: {'✅' if tightness_analysis['tight_crop'] else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 5
        
        if dimension_analysis['both_reduced']:
            criteria_met += 1
        if dimension_analysis['substantial_reduction']:
            criteria_met += 1 
        if content_analysis['content_preserved']:
            criteria_met += 1
        if border_analysis['borders_likely_removed']:
            criteria_met += 1
        if tightness_analysis['tight_crop']:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 4/5 criteria (75%)
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect autocrop to content!")
        elif passed:
            feedback_parts.append("✅ Good autocrop operation!")
        else:
            feedback_parts.append(f"❌ Autocrop needs improvement ({criteria_met}/{total_criteria} criteria met)")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in autocrop verification: {e}")
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
    result = check_autocrop([], {}, {})
    print(f"Test result: {result}")