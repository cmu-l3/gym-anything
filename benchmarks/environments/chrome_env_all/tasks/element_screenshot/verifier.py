#!/usr/bin/env python3
"""
Verifier for Chrome DOM Element Screenshot Task: element_screenshot@1
Task: Use DevTools to capture a screenshot of a specific DOM element

Verification Strategy:
1. Check Downloads folder for recently created PNG files
2. Verify screenshot dimensions are significantly smaller than viewport (element isolation)
3. Compare screenshot dimensions with expected element size
4. Ensure file format and metadata are correct
5. Validate file was created during task execution window
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, image analysis will be limited")

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


# Expected target element dimensions (from test HTML)
EXPECTED_ELEMENT_WIDTH = 450
EXPECTED_ELEMENT_HEIGHT = 180  # Approximate
DIMENSION_TOLERANCE = 0.15  # 15% tolerance

# Viewport assumptions (typical browser window)
TYPICAL_VIEWPORT_WIDTH = 1200
TYPICAL_VIEWPORT_HEIGHT = 800


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for element_screenshot@1 task.
    
    Verifies that agent successfully captured a screenshot of the target element
    using Chrome DevTools "Capture node screenshot" feature.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with 'passed' (bool), 'score' (int), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Find and retrieve screenshot file
        screenshot_files = find_screenshot_files(copy_from_env)
        
        if not screenshot_files:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No screenshot file found in Downloads folder. Did you use 'Capture node screenshot' in DevTools?"
            }
        
        # Analyze the most recent screenshot
        screenshot_path = screenshot_files[0]  # Already sorted by recency
        
        # Perform multi-criteria verification
        result = verify_element_screenshot(screenshot_path, copy_from_env)
        
        # Clean up temporary files
        cleanup_temp_files(screenshot_files)
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


def find_screenshot_files(copy_from_env) -> List[str]:
    """
    Find and copy screenshot files from container Downloads folder.
    
    Returns:
        List of local paths to screenshot files (sorted by recency)
    """
    temp_dir = Path(tempfile.gettempdir()) / "element_screenshot_verify"
    temp_dir.mkdir(exist_ok=True)
    
    screenshot_files = []
    
    try:
        # Try to get the list of screenshot filenames
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_list.close()
        
        try:
            copy_from_env("/tmp/element_screenshot_verification/screenshot_files.txt", temp_list.name)
            
            with open(temp_list.name, 'r') as f:
                filenames = [line.strip() for line in f if line.strip() and line.strip() != "none"]
            
            os.unlink(temp_list.name)
            
            if not filenames:
                logger.warning("No screenshot filenames found in screenshot_files.txt")
                return []
            
            # Copy each screenshot file
            for filename in filenames:
                try:
                    local_path = temp_dir / filename
                    container_path = f"/tmp/element_screenshot_verification/{filename}"
                    
                    logger.info(f"Attempting to copy screenshot: {container_path}")
                    copy_from_env(container_path, str(local_path))
                    
                    if local_path.exists() and local_path.stat().st_size > 0:
                        logger.info(f"✓ Successfully copied: {filename} ({local_path.stat().st_size} bytes)")
                        screenshot_files.append(str(local_path))
                    else:
                        logger.warning(f"File copied but empty or not found: {filename}")
                        
                except Exception as e:
                    logger.warning(f"Failed to copy {filename}: {e}")
                    
        except Exception as e:
            logger.warning(f"Could not read screenshot_files.txt: {e}")
            
            # Fallback: try to copy PNG files directly from /tmp/
            logger.info("Attempting fallback: searching for PNG files in /tmp/")
            fallback_patterns = [
                "/tmp/*.png",
                "/tmp/element_screenshot_verification/*.png"
            ]
            
            for pattern in fallback_patterns:
                try:
                    # We can't glob remotely, so try common filenames
                    common_names = [
                        "element_screenshot_test.png",
                        "localhost.png",
                        "screenshot.png"
                    ]
                    
                    for name in common_names:
                        try:
                            local_path = temp_dir / name
                            copy_from_env(f"/tmp/{name}", str(local_path))
                            if local_path.exists() and local_path.stat().st_size > 0:
                                screenshot_files.append(str(local_path))
                                logger.info(f"✓ Found via fallback: {name}")
                                break
                        except:
                            continue
                            
                except Exception as e2:
                    logger.debug(f"Fallback pattern {pattern} failed: {e2}")
        
        return screenshot_files
        
    except Exception as e:
        logger.error(f"Error finding screenshot files: {e}")
        return []


def verify_element_screenshot(screenshot_path: str, copy_from_env) -> Dict[str, Any]:
    """
    Verify that the screenshot is a valid element screenshot.
    
    Verification criteria:
    1. File exists and is valid PNG
    2. File has reasonable size (not empty, not suspiciously small)
    3. Dimensions are smaller than typical viewport (proves element isolation)
    4. Dimensions approximately match expected element size
    5. File created recently (within task execution window)
    
    Args:
        screenshot_path: Local path to screenshot file
        copy_from_env: Function to copy files from container
        
    Returns:
        Verification result dict
    """
    criteria_results = {}
    feedback_parts = []
    
    if not HAS_PIL:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Image processing library (Pillow) not available for verification"
        }
    
    # Criterion 1: File exists and is valid image
    try:
        img = Image.open(screenshot_path)
        img_format = img.format
        img_width, img_height = img.size
        
        criteria_results['valid_image'] = True
        feedback_parts.append(f"✓ Valid {img_format} image found: {img_width}x{img_height}px")
        logger.info(f"Image format: {img_format}, dimensions: {img_width}x{img_height}")
        
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid or corrupted image file: {e}"
        }
    
    # Criterion 2: File size check
    file_size = Path(screenshot_path).stat().st_size
    file_size_kb = file_size / 1024
    
    if file_size < 1024:  # Less than 1KB
        criteria_results['adequate_size'] = False
        feedback_parts.append(f"✗ File too small: {file_size} bytes")
    elif file_size < 5120:  # Less than 5KB
        criteria_results['adequate_size'] = False
        feedback_parts.append(f"✗ File suspiciously small: {file_size_kb:.1f} KB")
    else:
        criteria_results['adequate_size'] = True
        feedback_parts.append(f"✓ File size adequate: {file_size_kb:.1f} KB")
    
    # Criterion 3: Element isolation (smaller than viewport)
    # Calculate area ratio
    screenshot_area = img_width * img_height
    viewport_area = TYPICAL_VIEWPORT_WIDTH * TYPICAL_VIEWPORT_HEIGHT
    area_ratio = screenshot_area / viewport_area
    
    if area_ratio < 0.35:  # Less than 35% of typical viewport
        criteria_results['element_isolation'] = True
        feedback_parts.append(f"✓ Element isolation confirmed: {area_ratio:.1%} of typical viewport")
    else:
        criteria_results['element_isolation'] = False
        feedback_parts.append(f"✗ Screenshot too large: {area_ratio:.1%} of viewport (may be full page screenshot)")
    
    # Criterion 4: Dimension matching with expected element size
    width_diff_pct = abs(img_width - EXPECTED_ELEMENT_WIDTH) / EXPECTED_ELEMENT_WIDTH
    height_diff_pct = abs(img_height - EXPECTED_ELEMENT_HEIGHT) / EXPECTED_ELEMENT_HEIGHT
    
    # We use a more flexible check since element dimensions can vary with padding/borders
    if width_diff_pct <= DIMENSION_TOLERANCE and height_diff_pct <= 0.5:  # 50% tolerance for height
        criteria_results['dimensions_match'] = True
        feedback_parts.append(f"✓ Dimensions match target element: {img_width}x{img_height}px ≈ {EXPECTED_ELEMENT_WIDTH}x{EXPECTED_ELEMENT_HEIGHT}px")
    else:
        # Check if at least width is close (height can vary more with padding)
        if width_diff_pct <= 0.25:  # 25% tolerance
            criteria_results['dimensions_match'] = True
            feedback_parts.append(f"✓ Width matches target element: {img_width}px ≈ {EXPECTED_ELEMENT_WIDTH}px (height: {img_height}px)")
        else:
            criteria_results['dimensions_match'] = False
            feedback_parts.append(f"✗ Dimensions don't match: {img_width}x{img_height}px vs expected ~{EXPECTED_ELEMENT_WIDTH}x{EXPECTED_ELEMENT_HEIGHT}px")
    
    # Criterion 5: File recency (optional, partial credit)
    file_age = datetime.now().timestamp() - Path(screenshot_path).stat().st_mtime
    
    if file_age < 180:  # Less than 3 minutes old
        criteria_results['recent_file'] = True
        feedback_parts.append(f"✓ File created recently: {int(file_age)}s ago")
    else:
        criteria_results['recent_file'] = False
        feedback_parts.append(f"⚠ File age: {int(file_age)}s (may be from previous task)")
    
    # Calculate score
    # Core criteria: valid_image (required), adequate_size, element_isolation, dimensions_match
    # Bonus criterion: recent_file
    
    core_criteria = ['valid_image', 'adequate_size', 'element_isolation', 'dimensions_match']
    core_met = sum(criteria_results.get(c, False) for c in core_criteria)
    recent_met = criteria_results.get('recent_file', False)
    
    # Scoring:
    # 4/4 core + recent = 100%
    # 4/4 core = 95%
    # 3/4 core = 75%
    # 2/4 core = 50%
    # <2 core = 25% or less
    
    if core_met == 4:
        score = 100 if recent_met else 95
    elif core_met == 3:
        score = 75
    elif core_met == 2:
        score = 50
    else:
        score = 25
    
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCore criteria met: {core_met}/4"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not passed:
        feedback += "\n\nTroubleshooting tips:"
        if not criteria_results.get('element_isolation', False):
            feedback += "\n- Ensure you used 'Capture node screenshot' in DevTools, not full page screenshot"
        if not criteria_results.get('dimensions_match', False):
            feedback += "\n- Make sure you right-clicked on the correct element (div#target-card)"
        if not criteria_results.get('adequate_size', False):
            feedback += "\n- The screenshot file seems corrupted or incomplete"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={core_met}/4")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "image_dimensions": f"{img_width}x{img_height}",
            "file_size_kb": round(file_size_kb, 2),
            "area_ratio": round(area_ratio, 3),
            "criteria": criteria_results
        }
    }


def cleanup_temp_files(file_paths: List[str]):
    """Clean up temporary screenshot files"""
    for path in file_paths:
        try:
            if os.path.exists(path):
                os.unlink(path)
        except Exception as e:
            logger.debug(f"Failed to clean up {path}: {e}")
