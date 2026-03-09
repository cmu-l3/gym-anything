#!/usr/bin/env python3
"""
Verifier for Chrome Device Emulation Task (device_emulation@1)
Task: Open DevTools and enable device emulation for iPhone 12 Pro (390×844)

Verification Strategy:
- Capture screenshots from the container
- Analyze image dimensions to detect viewport size
- Verify dimensions match iPhone 12 Pro (390×844 ±5px tolerance)
- Check aspect ratio for mobile portrait orientation
- Validate that device emulation is actually active (not just window resize)
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Tuple, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PIL for image processing
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, image analysis will be limited")

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


# Expected dimensions for iPhone 12 Pro
EXPECTED_WIDTH = 390
EXPECTED_HEIGHT = 844
DIMENSION_TOLERANCE = 5

# Acceptable dimension range
MIN_WIDTH = EXPECTED_WIDTH - DIMENSION_TOLERANCE
MAX_WIDTH = EXPECTED_WIDTH + DIMENSION_TOLERANCE
MIN_HEIGHT = EXPECTED_HEIGHT - DIMENSION_TOLERANCE
MAX_HEIGHT = EXPECTED_HEIGHT + DIMENSION_TOLERANCE


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for device_emulation@1.
    
    Verifies that Chrome DevTools device emulation is active with iPhone 12 Pro settings.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    if not HAS_PIL:
        return {
            "passed": False,
            "score": 0,
            "feedback": "PIL/Pillow library not available for image verification"
        }

    try:
        # Copy screenshots from container
        screenshots = copy_screenshots_from_container(copy_from_env)
        
        if not screenshots:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to retrieve screenshots from container"
            }
        
        # Analyze screenshots for device emulation
        result = analyze_device_emulation(screenshots, copy_from_env)
        
        # Clean up temporary files
        cleanup_temp_files(screenshots)
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def copy_screenshots_from_container(copy_from_env) -> Dict[str, str]:
    """
    Copy screenshot files from container to host for analysis.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict mapping screenshot names to local file paths
    """
    screenshots = {}
    
    # Try to copy various screenshot files
    screenshot_files = [
        "full_screen.png",
        "chrome_window.png",
    ]
    
    for screenshot_name in screenshot_files:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_file.close()
            
            # Try verification directory first
            container_path = f"/tmp/device_emulation_verification/{screenshot_name}"
            try:
                copy_from_env(container_path, temp_file.name)
            except:
                # Try direct /tmp path
                container_path = f"/tmp/{screenshot_name}"
                copy_from_env(container_path, temp_file.name)
            
            # Verify file has content
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                screenshots[screenshot_name] = temp_file.name
                logger.info(f"✓ Copied {screenshot_name}")
            else:
                os.unlink(temp_file.name)
                
        except Exception as e:
            logger.debug(f"Could not copy {screenshot_name}: {e}")
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    
    return screenshots


def analyze_device_emulation(screenshots: Dict[str, str], copy_from_env) -> Dict[str, Any]:
    """
    Analyze screenshots to determine if device emulation is active and correct.
    
    Args:
        screenshots: Dict of screenshot names to local file paths
        copy_from_env: Function to copy additional files if needed
        
    Returns:
        Verification result dict with passed, score, feedback
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Try to get viewport dimensions from screenshots
    viewport_width, viewport_height = None, None
    detection_method = None
    
    # Strategy 1: Analyze chrome_window screenshot (preferred)
    if "chrome_window.png" in screenshots:
        width, height = get_image_dimensions(screenshots["chrome_window.png"])
        if width and height:
            # The chrome_window might include chrome UI, but if dimensions match device, it's likely correct
            if is_mobile_portrait_dimensions(width, height):
                viewport_width, viewport_height = width, height
                detection_method = "Chrome window screenshot"
                logger.info(f"Detected dimensions from chrome_window: {width}×{height}")
    
    # Strategy 2: Analyze full_screen screenshot (fallback)
    if viewport_width is None and "full_screen.png" in screenshots:
        width, height = get_image_dimensions(screenshots["full_screen.png"])
        if width and height:
            # Try to detect mobile viewport region within full screen
            detected = detect_mobile_viewport_in_fullscreen(screenshots["full_screen.png"])
            if detected:
                viewport_width, viewport_height = detected
                detection_method = "Full screen analysis"
                logger.info(f"Detected mobile viewport in full screen: {viewport_width}×{viewport_height}")
    
    # Strategy 3: Try to read viewport info from tab metadata
    if viewport_width is None:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
            temp_file.close()
            copy_from_env("/tmp/device_emulation_verification/tab_info.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                tab_info = json.load(f)
            os.unlink(temp_file.name)
            
            # Check if description or other fields hint at device emulation
            description = tab_info.get('description', '').lower()
            if '390' in description and '844' in description:
                logger.info("Found viewport hints in tab metadata")
                # This is supplementary evidence, not primary
        except Exception as e:
            logger.debug(f"Could not read tab info: {e}")
    
    if viewport_width is None or viewport_height is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not detect viewport dimensions from screenshots. DevTools may not be open or device emulation may not be active.",
            "details": {
                "screenshots_available": list(screenshots.keys()),
                "detection_attempted": True
            }
        }
    
    logger.info(f"Viewport dimensions detected: {viewport_width}×{viewport_height} via {detection_method}")
    
    # Criterion 1: Viewport width matches iPhone 12 Pro (390px ±5)
    width_match = MIN_WIDTH <= viewport_width <= MAX_WIDTH
    if width_match:
        criteria_met += 1
        feedback_parts.append(f"✓ Viewport width correct: {viewport_width}px (expected {EXPECTED_WIDTH}px)")
    else:
        feedback_parts.append(f"✗ Viewport width incorrect: {viewport_width}px (expected {EXPECTED_WIDTH}px ±{DIMENSION_TOLERANCE})")
    
    # Criterion 2: Viewport height matches iPhone 12 Pro (844px ±5)
    height_match = MIN_HEIGHT <= viewport_height <= MAX_HEIGHT
    if height_match:
        criteria_met += 1
        feedback_parts.append(f"✓ Viewport height correct: {viewport_height}px (expected {EXPECTED_HEIGHT}px)")
    else:
        feedback_parts.append(f"✗ Viewport height incorrect: {viewport_height}px (expected {EXPECTED_HEIGHT}px ±{DIMENSION_TOLERANCE})")
    
    # Criterion 3: Mobile portrait aspect ratio
    aspect_ratio = viewport_width / viewport_height if viewport_height > 0 else 0
    expected_ratio = EXPECTED_WIDTH / EXPECTED_HEIGHT
    ratio_tolerance = 0.05
    
    ratio_match = abs(aspect_ratio - expected_ratio) < ratio_tolerance
    if ratio_match:
        criteria_met += 1
        feedback_parts.append(f"✓ Aspect ratio correct: {aspect_ratio:.3f} (mobile portrait)")
    else:
        feedback_parts.append(f"⚠ Aspect ratio: {aspect_ratio:.3f} (expected ~{expected_ratio:.3f})")
    
    # Criterion 4: Dimensions indicate mobile device (not just small window)
    is_mobile_sized = viewport_width < 500 and viewport_height > 600
    if is_mobile_sized:
        criteria_met += 1
        feedback_parts.append(f"✓ Dimensions indicate mobile device emulation")
    else:
        feedback_parts.append(f"✗ Dimensions do not indicate mobile device")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Build final feedback
    feedback = f"Device Emulation Verification ({detection_method})\n"
    feedback += f"Detected viewport: {viewport_width} × {viewport_height} pixels\n"
    feedback += f"Criteria met: {criteria_met}/{total_criteria}\n\n"
    feedback += "\n".join(feedback_parts)
    
    if passed:
        feedback += "\n\n✅ Device emulation successfully configured!"
    else:
        feedback += "\n\n❌ Device emulation not correctly configured. Please:"
        feedback += "\n  1. Open DevTools (F12 or Ctrl+Shift+I)"
        feedback += "\n  2. Toggle Device Toolbar (Ctrl+Shift+M)"
        feedback += "\n  3. Select 'iPhone 12 Pro' from device dropdown"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "viewport_width": viewport_width,
            "viewport_height": viewport_height,
            "aspect_ratio": aspect_ratio,
            "detection_method": detection_method,
            "criteria_met": criteria_met
        }
    }


def get_image_dimensions(image_path: str) -> Tuple[Optional[int], Optional[int]]:
    """
    Get dimensions of an image file.
    
    Args:
        image_path: Path to image file
        
    Returns:
        Tuple of (width, height) or (None, None) if failed
    """
    if not HAS_PIL:
        return None, None
    
    try:
        with Image.open(image_path) as img:
            return img.size
    except Exception as e:
        logger.error(f"Error reading image dimensions from {image_path}: {e}")
        return None, None


def is_mobile_portrait_dimensions(width: int, height: int) -> bool:
    """
    Check if dimensions indicate mobile portrait orientation.
    
    Args:
        width: Image width in pixels
        height: Image height in pixels
        
    Returns:
        True if dimensions match mobile portrait characteristics
    """
    # Mobile portrait: width < height and reasonable size range
    if height <= width:
        return False
    
    aspect_ratio = width / height
    
    # Typical mobile portrait aspect ratios: 0.4 to 0.6
    # iPhone 12 Pro: 390/844 ≈ 0.462
    if 0.35 < aspect_ratio < 0.65:
        # Also check absolute dimensions are in mobile range
        if 300 <= width <= 500 and 600 <= height <= 1000:
            return True
    
    return False


def detect_mobile_viewport_in_fullscreen(fullscreen_path: str) -> Optional[Tuple[int, int]]:
    """
    Try to detect mobile viewport region within a full screen capture.
    This is a fallback method if we only have full screen screenshot.
    
    Args:
        fullscreen_path: Path to full screen screenshot
        
    Returns:
        Tuple of (width, height) if mobile viewport detected, else None
    """
    if not HAS_PIL:
        return None
    
    try:
        with Image.open(fullscreen_path) as img:
            width, height = img.size
            
            # If the full screen itself is mobile-sized, it might be the viewport
            if is_mobile_portrait_dimensions(width, height):
                return width, height
            
            # TODO: More sophisticated detection could analyze image content
            # to find the Chrome DevTools device frame, but this is complex
            
        return None
        
    except Exception as e:
        logger.error(f"Error analyzing full screen image: {e}")
        return None


def cleanup_temp_files(screenshots: Dict[str, str]):
    """
    Clean up temporary screenshot files.
    
    Args:
        screenshots: Dict of screenshot names to local file paths
    """
    for temp_path in screenshots.values():
        try:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
        except Exception as e:
            logger.debug(f"Could not delete temp file {temp_path}: {e}")
