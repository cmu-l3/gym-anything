#!/usr/bin/env python3
"""
Verifier for GIMP autocrop image task.
Checks if image was successfully autocropped to remove borders and whitespace.
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


def analyze_dimension_reduction(original_img, result_img):
    """
    Analyze if dimensions were meaningfully reduced by autocrop.
    """
    orig_width, orig_height = original_img.size
    result_width, result_height = result_img.size
    
    # Calculate reductions
    width_reduction = orig_width - result_width
    height_reduction = orig_height - result_height
    
    # Calculate reduction percentages
    width_reduction_pct = width_reduction / orig_width if orig_width > 0 else 0
    height_reduction_pct = height_reduction / orig_height if orig_height > 0 else 0
    
    # Check for meaningful reduction (at least 5% or 10 pixels in one dimension)
    width_reduced_significantly = (width_reduction >= 10 and width_reduction_pct >= 0.05)
    height_reduced_significantly = (height_reduction >= 10 and height_reduction_pct >= 0.05)
    
    # At least one dimension should be reduced significantly
    significantly_reduced = width_reduced_significantly or height_reduced_significantly
    
    return {
        'original_size': (orig_width, orig_height),
        'result_size': (result_width, result_height),
        'width_reduction': width_reduction,
        'height_reduction': height_reduction,
        'width_reduction_pct': width_reduction_pct,
        'height_reduction_pct': height_reduction_pct,
        'significantly_reduced': significantly_reduced
    }


def analyze_content_preservation(original_img, result_img):
    """
    Analyze if core content was preserved during autocrop.
    Uses center region comparison with SSIM.
    """
    try:
        from skimage.metrics import structural_similarity as ssim
    except ImportError:
        try:
            from skimage.measure import compare_ssim as ssim
        except ImportError:
            # Fallback: simple correlation analysis
            return analyze_content_preservation_fallback(original_img, result_img)
    
    # Convert to RGB if needed
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Extract center regions for comparison (60% of each image)
    orig_h, orig_w = orig_array.shape[:2]
    result_h, result_w = result_array.shape[:2]
    
    # Calculate center region bounds
    orig_y1, orig_y2 = int(orig_h * 0.2), int(orig_h * 0.8)
    orig_x1, orig_x2 = int(orig_w * 0.2), int(orig_w * 0.8)
    
    result_y1, result_y2 = int(result_h * 0.2), int(result_h * 0.8)
    result_x1, result_x2 = int(result_w * 0.2), int(result_w * 0.8)
    
    # Extract center regions
    orig_center = orig_array[orig_y1:orig_y2, orig_x1:orig_x2]
    result_center = result_array[result_y1:result_y2, result_x1:result_x2]
    
    if orig_center.size == 0 or result_center.size == 0:
        return {'content_preserved': False, 'similarity_score': 0.0}
    
    # Resize result center to match original center size for comparison
    from PIL import Image
    orig_center_img = Image.fromarray(orig_center.astype('uint8'))
    result_center_img = Image.fromarray(result_center.astype('uint8'))
    
    # Resize to match for comparison
    if orig_center_img.size != result_center_img.size:
        result_center_img = result_center_img.resize(orig_center_img.size, Image.LANCZOS)
    
    # Convert back to arrays
    orig_center_resized = np.array(orig_center_img)
    result_center_resized = np.array(result_center_img)
    
    try:
        # Calculate SSIM
        if orig_center_resized.shape[:2] >= (7, 7):  # Minimum size for SSIM
            try:
                similarity = ssim(orig_center_resized, result_center_resized, 
                                 multichannel=True, channel_axis=2, win_size=7)
            except TypeError:
                similarity = ssim(orig_center_resized, result_center_resized, 
                                 multichannel=True, win_size=7)
        else:
            # Too small for SSIM, use correlation
            similarity = np.corrcoef(orig_center_resized.flatten(), 
                                   result_center_resized.flatten())[0, 1]
            if np.isnan(similarity):
                similarity = 0.0
    except Exception as e:
        logging.debug(f"SSIM calculation failed: {e}")
        similarity = 0.0
    
    content_preserved = similarity >= 0.90  # High threshold for content preservation
    
    return {
        'content_preserved': content_preserved,
        'similarity_score': similarity
    }


def analyze_content_preservation_fallback(original_img, result_img):
    """Fallback content preservation analysis without scikit-image."""
    # Simple correlation-based analysis
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    # Extract center regions and calculate correlation
    orig_h, orig_w = orig_array.shape[:2]
    result_h, result_w = result_array.shape[:2]
    
    orig_center = orig_array[orig_h//4:3*orig_h//4, orig_w//4:3*orig_w//4]
    result_center = result_array[result_h//4:3*result_h//4, result_w//4:3*result_w//4]
    
    if orig_center.size == 0 or result_center.size == 0:
        return {'content_preserved': False, 'similarity_score': 0.0}
    
    # Resize for comparison
    from PIL import Image
    orig_center_img = Image.fromarray(orig_center.astype('uint8'))
    result_center_img = Image.fromarray(result_center.astype('uint8'))
    result_center_img = result_center_img.resize(orig_center_img.size)
    
    # Calculate correlation
    orig_flat = np.array(orig_center_img).flatten()
    result_flat = np.array(result_center_img).flatten()
    
    correlation = np.corrcoef(orig_flat, result_flat)[0, 1]
    if np.isnan(correlation):
        correlation = 0.0
    
    return {
        'content_preserved': correlation >= 0.85,  # Lower threshold for fallback
        'similarity_score': correlation
    }


def analyze_border_removal(original_img, result_img):
    """
    Analyze if border removal was effective by checking edge content density.
    """
    if original_img.mode != 'RGB':
        original_img = original_img.convert('RGB')
    if result_img.mode != 'RGB':
        result_img = result_img.convert('RGB')
    
    orig_array = np.array(original_img)
    result_array = np.array(result_img)
    
    def calculate_edge_content_density(img_array, border_width=20):
        """Calculate content density near image edges."""
        h, w = img_array.shape[:2]
        
        # Extract edge regions
        top_edge = img_array[:min(border_width, h//4), :]
        bottom_edge = img_array[max(0, h-border_width):, :]
        left_edge = img_array[:, :min(border_width, w//4)]
        right_edge = img_array[:, max(0, w-border_width):]
        
        # Calculate variance (measure of content/detail) in each edge
        edges = [top_edge, bottom_edge, left_edge, right_edge]
        edge_variances = []
        
        for edge in edges:
            if edge.size > 0:
                # Convert to grayscale for variance calculation
                if len(edge.shape) == 3:
                    edge_gray = np.mean(edge, axis=2)
                else:
                    edge_gray = edge
                edge_variances.append(np.var(edge_gray))
            else:
                edge_variances.append(0)
        
        return np.mean(edge_variances)
    
    # Calculate edge content density for both images
    orig_edge_density = calculate_edge_content_density(orig_array)
    result_edge_density = calculate_edge_content_density(result_array)
    
    # After good autocrop, edge regions should have higher content density
    edge_improvement = result_edge_density / (orig_edge_density + 1e-6)  # Avoid division by zero
    borders_removed_well = edge_improvement >= 1.2  # 20% improvement in edge content density
    
    return {
        'original_edge_density': orig_edge_density,
        'result_edge_density': result_edge_density,
        'edge_improvement': edge_improvement,
        'borders_removed_well': borders_removed_well
    }


def check_autocrop_image(traj, env_info, task_info):
    """
    Main verifier function for autocrop image task.
    Checks:
    1. Image dimensions were significantly reduced
    2. Core content was preserved
    3. Border removal was effective
    4. Result appears professionally cropped
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
        "/home/ga/Desktop/bordered_image_autocrop.jpg"
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
        
        # Analyze dimension reduction
        dimension_analysis = analyze_dimension_reduction(original_image, result_image)
        
        # Analyze content preservation
        content_analysis = analyze_content_preservation(original_image, result_image)
        
        # Analyze border removal effectiveness
        border_analysis = analyze_border_removal(original_image, result_image)
        
        # Check if image was modified at all
        images_different = original_image.size != result_image.size
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {dimension_analysis['original_size']}")
        feedback_parts.append(f"Result size: {dimension_analysis['result_size']}")
        feedback_parts.append(f"Width reduction: {dimension_analysis['width_reduction']}px ({dimension_analysis['width_reduction_pct']:.1%})")
        feedback_parts.append(f"Height reduction: {dimension_analysis['height_reduction']}px ({dimension_analysis['height_reduction_pct']:.1%})")
        feedback_parts.append(f"Significantly reduced: {'✅' if dimension_analysis['significantly_reduced'] else '❌'}")
        feedback_parts.append(f"Content preserved: {'✅' if content_analysis['content_preserved'] else '❌'} (similarity: {content_analysis['similarity_score']:.3f})")
        feedback_parts.append(f"Borders removed well: {'✅' if border_analysis['borders_removed_well'] else '❌'} (improvement: {border_analysis['edge_improvement']:.2f}x)")
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate success based on multiple criteria
        criteria_met = 0
        total_criteria = 4
        
        if dimension_analysis['significantly_reduced']:
            criteria_met += 1
        if content_analysis['content_preserved']:
            criteria_met += 1
        if border_analysis['borders_removed_well']:
            criteria_met += 1
        if images_different:
            criteria_met += 1
        
        # Score based on criteria met
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect autocrop operation!")
        elif passed:
            feedback_parts.append("✅ Good autocrop operation!")
        else:
            feedback_parts.append("❌ Autocrop operation needs improvement")
            
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
    result = check_autocrop_image([], {}, {})
    print(f"Test result: {result}")