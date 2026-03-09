"""
Verifier for horizontal mirror task.
Checks that the result image is a horizontal mirror of the original.
"""

import os
import sys
import tempfile
import logging
from pathlib import Path
from PIL import Image
import numpy as np

# Set up logging
logging.basicConfig(level=logging.DEBUG)

try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    # Fallback for older versions
    from skimage.measure import compare_ssim as ssim


def structure_check_by_ssim(img1, img2, threshold=0.9):
    """Check if two images are approximately the same by SSIM"""
    min_size = 7
    if img1.width < min_size or img1.height < min_size or \
       img2.width < min_size or img2.height < min_size:
        logging.warning(f"image too small for ssim: {img1.size} vs {img2.size}")
        return False
    
    if img1.mode != 'RGB':
        img1 = img1.convert('RGB')
    if img2.mode != 'RGB':
        img2 = img2.convert('RGB')
    
    # Now both images are in RGB mode, so they should have the same number of channels (3)
    # But we still need to check the size (though the caller should have checked)
    if img1.size != img2.size:
        # If the sizes are different, we cannot compare, return False
        logging.debug(f"Images have different sizes: {img1.size} vs {img2.size}")
        return False

    array1 = np.array(img1)
    array2 = np.array(img2)
    # They should have the same shape now, but double check
    if array1.shape != array2.shape:
        logging.debug(f"Images have different shapes after conversion: {array1.shape} vs {array2.shape}")
        return False

    # Determine the window size for SSIM
    min_dim = min(array1.shape[0], array1.shape[1])
    if min_dim < 7:
        # If the smallest dimension is less than 7, set win_size to the next smaller odd number
        win_size = min_dim if min_dim % 2 == 1 else min_dim - 1
        if win_size < 1:
            logging.debug("Image too small for SSIM computation (min dimension < 1)")
            return False
    else:
        win_size = 7  # default

    try:
        # For newer versions of skimage, we use channel_axis, for older versions, multichannel
        # We try to use the newer way first, then fall back to the old way
        try:
            # Newer versions (channel_axis is available)
            similarity = ssim(array1, array2, win_size=win_size, channel_axis=2)
        except TypeError:
            # Older versions use multichannel
            similarity = ssim(array1, array2, win_size=win_size, multichannel=True)
    except Exception as e:
        logging.error(f"SSIM computation failed: {e}")
        return False

    logging.debug("SSIM: %s", similarity)
    return similarity >= threshold


def copy_file_from_container(copy_from_env_fn, container_path, host_path):
    """Copy a file from Docker container to host using env copy utilities."""
    try:
        copy_from_env_fn(container_path, str(host_path))
        return True, ""
    except Exception as e:
        return False, f"Failed to copy {container_path}: {str(e)}"


def check_image_mirror(traj, env_info, task_info):
    """
    Main verifier function for horizontal mirror task.
    
    Args:
        traj: Trajectory data with episode information
        env_info: Environment information including episode directory and copy utilities
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
        container_original = "/home/ga/Desktop/berry.png"
        container_mirrored = "/home/ga/Desktop/berry_mirror.png"
        
        # Define host paths
        host_original = temp_path / "berry.png"
        host_mirrored = temp_path / "berry_mirror.png"
        
        # Try to copy original image from container
        success, error = copy_file_from_container(copy_from_env, container_original, host_original)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access original image: {error}"
            }
        
        # Try to copy mirrored image from container
        success, error = copy_file_from_container(copy_from_env, container_mirrored, host_mirrored)
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access mirrored image: {error}. Make sure the image was exported as berry_mirror.png"
            }
        
        try:
            # Load images from copied files
            source_image = Image.open(host_original)
            target_image = Image.open(host_mirrored)
            
            # Check if the image is mirrored
            transposed_image = source_image.transpose(Image.FLIP_LEFT_RIGHT)
            
            # Use 0.99 because the image may not be exactly mirrored by GIMP
            mirrored = structure_check_by_ssim(transposed_image, target_image, 0.99)
            
            feedback_parts = []
            feedback_parts.append(f"Original size: {source_image.size}")
            feedback_parts.append(f"Result size: {target_image.size}")
            feedback_parts.append(f"Horizontally mirrored: {'✅' if mirrored else '❌'}")
            
            if mirrored:
                feedback_parts.append("🎉 Image successfully mirrored horizontally!")
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": " | ".join(feedback_parts)
                }
            else:
                feedback_parts.append("❌ Image was not mirrored correctly")
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": " | ".join(feedback_parts)
                }
            
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error during verification: {str(e)}"
            }
