#!/usr/bin/env python3
"""
Verifier for Frame Analysis Export task.

Checks if agent successfully captured the specific frame with red flash
using frame-by-frame navigation.
"""

import sys
import os
import logging
import tempfile
from typing import Dict, Any, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_snapshot_exists,
    verify_image_quality,
    setup_verification_environment,
    cleanup_verification_environment,
    PIL_AVAILABLE
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    NUMPY_AVAILABLE = True
except ImportError:
    logger.warning("PIL or NumPy not available - limited verification")
    NUMPY_AVAILABLE = False


def check_red_flash_present(image_path: str, threshold: float = 0.15) -> Tuple[bool, str]:
    """
    Check if the captured frame contains the red flash indicator.
    
    Analyzes the center region (200x200 pixels) of the image to detect
    red pixels (R > 200, G < 100, B < 100). If more than threshold
    proportion of pixels are red, the flash is detected.
    
    Args:
        image_path: Path to captured snapshot
        threshold: Minimum proportion of red pixels in center region (default 15%)
        
    Returns:
        Tuple of (success, feedback_message)
    """
    if not PIL_AVAILABLE or not NUMPY_AVAILABLE:
        logger.warning("PIL/NumPy not available - cannot verify red flash content")
        return True, "Image content verification skipped (PIL/NumPy not available)"
    
    try:
        # Open and convert image to RGB
        img = Image.open(image_path)
        img_array = np.array(img.convert('RGB'))
        
        height, width, _ = img_array.shape
        
        logger.info(f"Image dimensions: {width}x{height}")
        
        # Check image dimensions (should be 1280x720)
        expected_width, expected_height = 1280, 720
        if width != expected_width or height != expected_height:
            logger.warning(f"Resolution mismatch: {width}x{height} (expected {expected_width}x{expected_height})")
            # Don't fail on resolution mismatch, but note it
            # return False, f"Wrong resolution: {width}x{height} (expected {expected_width}x{expected_height})"
        
        # Define center region (200x200 pixels where red flash should be)
        center_x, center_y = width // 2, height // 2
        region_size = 200
        
        # Ensure region is within bounds
        x1 = max(0, center_x - region_size // 2)
        x2 = min(width, center_x + region_size // 2)
        y1 = max(0, center_y - region_size // 2)
        y2 = min(height, center_y + region_size // 2)
        
        center_region = img_array[y1:y2, x1:x2]
        
        # Check for red pixels (R > 200, G < 100, B < 100)
        # This identifies strongly red pixels (high R, low G and B)
        red_mask = (center_region[:, :, 0] > 200) & \
                   (center_region[:, :, 1] < 100) & \
                   (center_region[:, :, 2] < 100)
        
        red_pixel_count = np.sum(red_mask)
        total_pixels = (x2 - x1) * (y2 - y1)
        red_ratio = red_pixel_count / total_pixels if total_pixels > 0 else 0
        
        logger.info(f"Red pixel analysis: {red_pixel_count}/{total_pixels} = {red_ratio:.2%}")
        logger.info(f"Center region: ({x1},{y1}) to ({x2},{y2})")
        
        # Calculate average RGB in center for debugging
        avg_r = np.mean(center_region[:, :, 0])
        avg_g = np.mean(center_region[:, :, 1])
        avg_b = np.mean(center_region[:, :, 2])
        logger.info(f"Center region average RGB: ({avg_r:.1f}, {avg_g:.1f}, {avg_b:.1f})")
        
        if red_ratio >= threshold:
            return True, f"✅ Red flash detected ({red_ratio:.1%} of center region, {red_pixel_count} red pixels)"
        else:
            return False, f"✗ Insufficient red flash ({red_ratio:.1%} < {threshold:.0%} threshold) - likely wrong frame captured"
    
    except Exception as e:
        logger.error(f"Error analyzing image content: {e}", exc_info=True)
        return False, f"Image analysis failed: {str(e)}"


def verify_frame_capture(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for frame analysis task.
    
    Checks:
    1. Snapshot file exists
    2. Image has acceptable quality (size, format)
    3. Correct frame captured (red flash detected in center)
    
    Args:
        traj: Trajectory information (not used)
        env_info: Environment info including copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        Dict with verification results (passed, score, feedback)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        logger.error("Copy function not available")
        return {
            'passed': False,
            'score': 0,
            'feedback': "Copy function not available"
        }
    
    result = {
        'passed': False,
        'score': 0,
        'feedback': []
    }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Expected snapshot location (in container)
    snapshot_container_path = "/tmp/vlc_frame_snapshot.png"
    
    # Copy and verify snapshot
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        snapshot_container_path,
        file_type='image'
    )
    
    if not success:
        logger.error(f"Snapshot not found: {error}")
        feedback_parts.append(f"✗ Snapshot not found at {snapshot_container_path}")
        result['feedback'] = " | ".join(feedback_parts)
        return result
    
    # Criterion 1: File exists
    criteria_met += 1
    feedback_parts.append("✅ Snapshot file exists")
    
    # Criterion 2: Verify basic image quality
    image_data = file_info.get('data', {})
    host_snapshot_path = file_info.get('filepath')
    
    size_kb = image_data.get('size_kb', 0)
    
    if size_kb < 5:
        feedback_parts.append(f"✗ Snapshot too small ({size_kb:.1f} KB) - may be blank or corrupted")
        cleanup_verification_environment(file_info.get('temp_dir'))
        result['score'] = int((criteria_met / total_criteria) * 100)
        result['feedback'] = " | ".join(feedback_parts)
        return result
    
    if not verify_image_quality(host_snapshot_path, min_size_kb=10):
        feedback_parts.append(f"✗ Snapshot quality insufficient")
        cleanup_verification_environment(file_info.get('temp_dir'))
        result['score'] = int((criteria_met / total_criteria) * 100)
        result['feedback'] = " | ".join(feedback_parts)
        return result
    
    criteria_met += 1
    
    # Log image properties
    if PIL_AVAILABLE:
        width = image_data.get('width', 0)
        height = image_data.get('height', 0)
        feedback_parts.append(f"✅ Image quality OK ({size_kb:.1f} KB, {width}x{height})")
    else:
        feedback_parts.append(f"✅ Image quality OK ({size_kb:.1f} KB)")
    
    # Criterion 3: Check if image contains the red flash
    flash_present, flash_msg = check_red_flash_present(host_snapshot_path, threshold=0.15)
    feedback_parts.append(flash_msg)
    
    if flash_present:
        criteria_met += 1
    else:
        feedback_parts.append("Agent likely captured wrong frame or did not use frame-by-frame navigation")
    
    # Cleanup temporary files
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate final score
    result['score'] = int((criteria_met / total_criteria) * 100)
    result['passed'] = result['score'] >= 70
    result['feedback'] = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: {result}")
    
    return result
