"""
Verifier for brightness reduction task.
Checks that the edited image has reduced brightness while maintaining structural similarity.
"""

import os
import sys
import tempfile
from pathlib import Path
from PIL import Image
import numpy as np


def calculate_brightness(img):
    """Calculate average brightness of an image."""
    if img.mode == 'RGBA':
        img = img.convert('RGB')
    elif img.mode not in ['RGB', 'L']:
        img = img.convert('RGB')
    
    # Convert to grayscale and calculate mean
    grayscale = img.convert('L')
    return np.array(grayscale).mean()


def normalize_brightness(img, target_brightness=128):
    """Normalize image brightness to target level for comparison."""
    if img.mode == 'RGBA':
        img = img.convert('RGB')
    
    # Calculate current brightness
    current_brightness = calculate_brightness(img)
    
    if current_brightness == 0:
        return img
    
    # Calculate adjustment factor
    factor = target_brightness / current_brightness
    
    # Apply brightness adjustment
    img_array = np.array(img).astype(np.float32)
    img_array = img_array * factor
    img_array = np.clip(img_array, 0, 255).astype(np.uint8)
    
    return Image.fromarray(img_array)


def structure_check_by_mse(img1, img2, threshold=0.03):
    """Check structural similarity using MSE after brightness normalization."""
    # Ensure same size
    if img1.size != img2.size:
        img2 = img2.resize(img1.size, Image.LANCZOS)
    
    # Convert to numpy arrays
    arr1 = np.array(img1.convert('RGB')).astype(np.float32)
    arr2 = np.array(img2.convert('RGB')).astype(np.float32)
    
    # Calculate MSE
    mse = np.mean((arr1 - arr2) ** 2) / (255.0 ** 2)
    
    return mse <= threshold


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def list_container_files(exec_fn, container_path):
    """List files in container directory using env exec utilities."""
    try:
        # Note: This still uses direct exec, but through the runner's exec method
        # We could improve this by adding an exec utility to env_info as well
        result = exec_fn(f"find {container_path} -name '*.png' -type f")
        # The exec result might be different format, we'll handle it
        if hasattr(result, 'stdout'):
            files = [f.strip() for f in result.stdout.split('\n') if f.strip()]
        else:
            # If result is just the output string
            files = [f.strip() for f in str(result).split('\n') if f.strip()]
        return files, ""
    except Exception as e:
        return [], f"Failed to list files in {container_path}: {str(e)}"


def check_brightness_reduction(traj, env_info, task_info):
    """
    Main verifier function for brightness reduction task.
    
    Args:
        traj: Trajectory data with episode information
        env_info: Environment information including episode directory
        task_info: Task information
        
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    
    # Get episode directory and copy utilities
    episode_dir = env_info.get("episode_dir")
    copy_from_env = env_info.get("copy_from_env")
    
    if not episode_dir:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No episode directory found"
        }
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No copy utilities available"
        }
    
    # Create temporary directory for copied files
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Define container paths
        container_original = "/home/ga/Desktop/woman_sitting_by_the_tree.png"
        container_edited = "/home/ga/Desktop/edited_darker.png"
        
        # Define host paths
        host_original = temp_path / "original.png"
        host_edited = temp_path / "edited.png"
        
        # Try to copy original image from container
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original image: {error}"
            }
        
        # Try to copy edited image from container
        success, error = copy_file_from_container(copy_from_env, container_edited, host_edited)
        if not success:
            # For now, try a simple fallback approach
            # We could add exec utilities to env_info in the future for more sophisticated file listing
            # Try common variations of the edited filename
            common_variations = [
                "/home/ga/Desktop/edited_darker.png",
                "/home/ga/Desktop/woman_sitting_by_the_tree_edited.png", 
                "/home/ga/Desktop/edited.png",
                "/home/ga/Desktop/result.png",
                "/home/ga/Desktop/output.png"
            ]
            
            found_file = None
            for variation in common_variations:
                success, error = copy_file_from_container(copy_from_env, variation, host_edited)
                if success:
                    found_file = variation
                    break
            
            if not found_file:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"No edited image found. Tried variations: {[Path(v).name for v in common_variations]}"
                }
    
        try:
            # Load images from copied files
            img_original = Image.open(host_original)
            img_edited = Image.open(host_edited)
            
            # Calculate brightness
            brightness_original = calculate_brightness(img_original)
            brightness_edited = calculate_brightness(img_edited)
            
            # Check if brightness was reduced (edited should be darker)
            brightness_reduced = brightness_edited < brightness_original
            brightness_diff = brightness_original - brightness_edited
            
            # Normalize and compare structural similarity
            img_original_normalized = normalize_brightness(img_original, 128)
            img_edited_normalized = normalize_brightness(img_edited, 128)
            
            structure_similar = structure_check_by_mse(img_original_normalized, img_edited_normalized, threshold=0.03)
            
            # Determine success
            passed = brightness_reduced and structure_similar
            
            feedback_parts = []
            feedback_parts.append(f"Original brightness: {brightness_original:.1f}")
            feedback_parts.append(f"Edited brightness: {brightness_edited:.1f}")
            feedback_parts.append(f"Brightness difference: {brightness_diff:.1f}")
            feedback_parts.append(f"Brightness reduced: {'✅' if brightness_reduced else '❌'}")
            feedback_parts.append(f"Structure preserved: {'✅' if structure_similar else '❌'}")
            
            if passed:
                feedback_parts.append("🎉 Task completed successfully!")
            else:
                if not brightness_reduced:
                    feedback_parts.append("❌ Brightness was not reduced enough")
                if not structure_similar:
                    feedback_parts.append("❌ Image structure was changed too much")
            
            return {
                "passed": passed,
                "score": 100 if passed else 0,
                "feedback": " | ".join(feedback_parts)
            }
            
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error during verification: {str(e)}"
            }
