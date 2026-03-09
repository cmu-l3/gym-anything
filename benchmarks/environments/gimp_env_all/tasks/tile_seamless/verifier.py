#!/usr/bin/env python3
"""
Verifier for GIMP tile seamless task.
Checks if Tile Seamless filter was applied to make image edges match for tiling.
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


def extract_edges(img, edge_width=10):
    """Extract edge strips from image for comparison."""
    img_array = np.array(img.convert('RGB'))
    height, width = img_array.shape[:2]
    
    # Adjust edge width based on image size
    edge_width = min(edge_width, width // 20, height // 20, 15)
    edge_width = max(edge_width, 3)  # Minimum 3 pixels
    
    edges = {
        'left': img_array[:, :edge_width, :],
        'right': img_array[:, -edge_width:, :],
        'top': img_array[:edge_width, :, :],
        'bottom': img_array[-edge_width:, :, :]
    }
    
    return edges, edge_width


def calculate_edge_similarity(edge1, edge2):
    """Calculate similarity between two edge arrays using MSE."""
    if edge1.shape != edge2.shape:
        return float('inf')  # Very different if shapes don't match
    
    # Calculate Mean Squared Error
    mse = np.mean((edge1.astype(float) - edge2.astype(float)) ** 2)
    return mse


def simulate_tiling_seams(img):
    """
    Simulate 2x2 tiling and analyze seam visibility.
    Lower variance across seam indicates better seamless quality.
    """
    width, height = img.size
    tiled = Image.new('RGB', (width * 2, height * 2))
    
    # Place image in 2x2 grid
    for i in range(2):
        for j in range(2):
            tiled.paste(img, (i * width, j * height))
    
    tiled_array = np.array(tiled.convert('RGB'))
    
    # Analyze seam regions (junction areas between tiles)
    seam_width = min(10, width // 40, height // 40)
    seam_width = max(seam_width, 2)
    
    # Horizontal seam (across center)
    h_start = height - seam_width
    h_end = height + seam_width
    horizontal_seam = tiled_array[h_start:h_end, :, :]
    
    # Vertical seam (across center)  
    v_start = width - seam_width
    v_end = width + seam_width
    vertical_seam = tiled_array[:, v_start:v_end, :]
    
    # Calculate variance across seams (lower = smoother = better)
    h_variance = np.var(horizontal_seam, axis=0).mean() if horizontal_seam.size > 0 else 1000
    v_variance = np.var(vertical_seam, axis=1).mean() if vertical_seam.size > 0 else 1000
    
    avg_variance = (h_variance + v_variance) / 2
    
    return avg_variance


def detect_seamless_processing(original_img, result_img):
    """
    Detect if seamless processing was applied by analyzing edge modifications.
    """
    # Ensure images are same size
    if original_img.size != result_img.size:
        result_img = result_img.resize(original_img.size)
    
    # Extract edges from both images
    orig_edges, edge_width = extract_edges(original_img)
    result_edges, _ = extract_edges(result_img)
    
    # Calculate how much edges were modified (indicates processing)
    edge_modifications = {}
    for edge_name in ['left', 'right', 'top', 'bottom']:
        orig_edge = orig_edges[edge_name]
        result_edge = result_edges[edge_name]
        
        # Calculate difference between original and result edges
        if orig_edge.shape == result_edge.shape:
            modification = np.mean(np.abs(orig_edge.astype(float) - result_edge.astype(float)))
            edge_modifications[edge_name] = modification
        else:
            edge_modifications[edge_name] = 0
    
    avg_edge_modification = np.mean(list(edge_modifications.values()))
    
    return {
        'edge_modifications': edge_modifications,
        'avg_edge_modification': avg_edge_modification,
        'processing_detected': avg_edge_modification > 5  # Threshold for meaningful processing
    }


def verify_edge_matching(img):
    """Verify that opposing edges match for seamless tiling."""
    edges, edge_width = extract_edges(img)
    
    # Compare left vs right edges
    lr_similarity = calculate_edge_similarity(edges['left'], edges['right'])
    
    # Compare top vs bottom edges  
    tb_similarity = calculate_edge_similarity(edges['top'], edges['bottom'])
    
    # Thresholds for acceptable edge matching (MSE values)
    similarity_threshold = 400  # Adjust based on testing
    
    lr_match = lr_similarity < similarity_threshold
    tb_match = tb_similarity < similarity_threshold
    
    return {
        'lr_similarity': lr_similarity,
        'tb_similarity': tb_similarity,
        'lr_match': lr_match,
        'tb_match': tb_match,
        'edge_width': edge_width
    }


def check_tile_seamless(traj, env_info, task_info):
    """
    Main verifier function for tile seamless task.
    Checks:
    1. Left-right edges match for horizontal tiling
    2. Top-bottom edges match for vertical tiling  
    3. Simulated tiling shows minimal visible seams
    4. Image was modified (filter applied)
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
        "/home/ga/Desktop/seamless_texture.png",
        "/home/ga/Desktop/seamless_texture.jpg", 
        "/home/ga/Desktop/seamless_texture.jpeg",
        "/home/ga/Desktop/texture_seamless.png",
        "/home/ga/Desktop/texture_image_seamless.jpg",
        "/home/ga/Desktop/texture_image_edited.jpg"
    ]
    
    success, file_info = setup_verification_environment(
        "/home/ga/Desktop/texture_image.jpg",
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
        
        # Verify edge matching for seamless tiling
        edge_analysis = verify_edge_matching(result_image)
        
        # Analyze tiling seam quality
        seam_variance = simulate_tiling_seams(result_image)
        seam_quality_good = seam_variance < 500  # Threshold for acceptable seam visibility
        
        # Detect if processing was applied
        processing_analysis = detect_seamless_processing(original_image, result_image)
        
        # Check if image was meaningfully modified
        images_different = processing_analysis['processing_detected'] or not np.array_equal(
            np.array(original_image), np.array(result_image.convert(original_image.mode))
        )
        
        feedback_parts = []
        feedback_parts.append(f"Original size: {original_image.size}")
        feedback_parts.append(f"Result size: {result_image.size}")
        feedback_parts.append(f"Edge analysis width: {edge_analysis['edge_width']} pixels")
        feedback_parts.append(f"Left-Right MSE: {edge_analysis['lr_similarity']:.1f}")
        feedback_parts.append(f"Top-Bottom MSE: {edge_analysis['tb_similarity']:.1f}")
        feedback_parts.append(f"Tiling seam variance: {seam_variance:.1f}")
        feedback_parts.append(f"Edge processing detected: {processing_analysis['avg_edge_modification']:.1f}")
        
        # Evaluate success criteria
        criteria_met = 0
        total_criteria = 4
        
        # 1. Left-Right edges match
        if edge_analysis['lr_match']:
            criteria_met += 1
        feedback_parts.append(f"Left-Right edges match: {'✅' if edge_analysis['lr_match'] else '❌'}")
        
        # 2. Top-Bottom edges match
        if edge_analysis['tb_match']:
            criteria_met += 1
        feedback_parts.append(f"Top-Bottom edges match: {'✅' if edge_analysis['tb_match'] else '❌'}")
        
        # 3. Good seam quality in tiled simulation
        if seam_quality_good:
            criteria_met += 1
        feedback_parts.append(f"Low seam visibility: {'✅' if seam_quality_good else '❌'}")
        
        # 4. Image was modified
        if images_different:
            criteria_met += 1
        feedback_parts.append(f"Image modified: {'✅' if images_different else '❌'}")
        
        # Calculate score and pass/fail
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria
        
        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect seamless tiling achieved!")
        elif passed:
            feedback_parts.append("✅ Good seamless tiling!")
        else:
            feedback_parts.append("❌ Seamless tiling needs improvement")
            
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logging.error(f"Error in tile seamless verification: {e}")
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
    result = check_tile_seamless([], {}, {})
    print(f"Test result: {result}")