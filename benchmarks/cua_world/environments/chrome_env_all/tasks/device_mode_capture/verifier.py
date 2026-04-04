#!/usr/bin/env python3
"""
Verifier for Chrome Device Mode Emulation and Capture Task (device_mode_capture@1)
Task: Use DevTools Device Mode to emulate iPhone SE viewport and capture screenshot

Verification Strategy:
1. Find screenshot file in Downloads folder (created during task execution)
2. Verify image dimensions match iPhone SE viewport (375x667 pixels)
3. Validate image is not blank/empty
4. Check file was created during task timeframe
5. Ensure image has reasonable content (not solid color)
"""

import logging
import sys
import os
import time
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PIL for image processing
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available - image dimension verification will be limited")


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for device_mode_capture@1 task.
    
    Verifies:
    1. Screenshot file exists in Downloads folder
    2. Screenshot has correct dimensions (375x667 pixels ±5px)
    3. Screenshot was created during task execution
    4. Image is valid and contains content
    5. Image is not blank or nearly blank
    
    Scoring:
    - 100%: All 5 criteria met (perfect execution)
    - 80-99%: 4/5 criteria met (minor issue)
    - 60-79%: 3/5 criteria met (partial success)
    - 40-59%: 2/5 criteria met (significant issues)
    - 0-39%: 0-1 criteria met (task failed)
    
    Pass threshold: 75% (requires at least 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    if not HAS_PIL:
        return {
            "passed": False,
            "score": 0,
            "feedback": "PIL/Pillow library not available - cannot verify image dimensions"
        }

    try:
        # Get task start time
        task_start_time = get_task_start_time(copy_from_env)
        logger.info(f"Task start time: {task_start_time} ({time.ctime(task_start_time)})")
        
        # Find screenshot file
        screenshot_path, screenshot_info, find_error = find_screenshot_file(
            copy_from_env, 
            task_start_time
        )
        
        if not screenshot_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No screenshot found in Downloads folder. {find_error}"
            }
        
        logger.info(f"Found screenshot: {screenshot_info['filename']}")
        
        # Verify screenshot with multiple criteria
        verification_result = verify_screenshot_comprehensive(
            screenshot_path,
            screenshot_info,
            task_start_time
        )
        
        # Clean up temporary files
        cleanup_temp_file(screenshot_path)
        
        return verification_result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_task_start_time(copy_from_env) -> float:
    """
    Get task start timestamp from container.
    
    Returns:
        Unix timestamp (float), defaults to 5 minutes ago if not found
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/task_start_time.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            start_time = float(f.read().strip())
        
        os.unlink(temp_file.name)
        return start_time
        
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}, using default")
        return time.time() - 300  # Default: 5 minutes ago


def find_screenshot_file(copy_from_env, task_start_time: float) -> Tuple[Optional[str], Dict, str]:
    """
    Find and copy the most recent screenshot from Downloads folder.
    
    Args:
        copy_from_env: Function to copy files from container
        task_start_time: Task start timestamp for filtering
        
    Returns:
        Tuple of (local_path, screenshot_info_dict, error_message)
    """
    try:
        # Get list of downloads
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_list.close()
        
        try:
            copy_from_env("/tmp/device_mode_verification/downloads_list.txt", temp_list.name)
        except Exception as e:
            logger.error(f"Could not copy downloads list: {e}")
            return None, {}, "Could not access Downloads folder information"
        
        # Parse downloads list
        with open(temp_list.name, 'r') as f:
            downloads = f.readlines()
        
        os.unlink(temp_list.name)
        
        if not downloads:
            return None, {}, "No image files found in Downloads folder"
        
        # Find screenshots created after task start
        candidates = []
        for line in downloads:
            parts = line.strip().split(maxsplit=1)
            if len(parts) < 2:
                continue
            
            file_mtime = float(parts[0])
            file_path = parts[1]
            
            # Only consider files created after task start
            if file_mtime < task_start_time:
                logger.debug(f"Skipping old file: {file_path} (mtime: {file_mtime})")
                continue
            
            candidates.append({
                'path': file_path,
                'mtime': file_mtime,
                'filename': os.path.basename(file_path)
            })
        
        if not candidates:
            return None, {}, f"No screenshots created after task start ({time.ctime(task_start_time)})"
        
        # Sort by modification time (most recent first)
        candidates.sort(key=lambda x: x['mtime'], reverse=True)
        
        # Prefer files with 'example' or 'screenshot' in name
        priority_candidates = [
            c for c in candidates 
            if any(kw in c['filename'].lower() for kw in ['example', 'screenshot', 'capture'])
        ]
        
        selected = priority_candidates[0] if priority_candidates else candidates[0]
        
        logger.info(f"Selected screenshot: {selected['filename']} (from {len(candidates)} candidates)")
        
        # Copy the screenshot file
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_screenshot.close()
        
        try:
            copy_from_env(selected['path'], temp_screenshot.name)
        except Exception as e:
            logger.error(f"Failed to copy screenshot: {e}")
            return None, {}, f"Could not copy screenshot file: {e}"
        
        # Verify file was copied successfully
        if not os.path.exists(temp_screenshot.name) or os.path.getsize(temp_screenshot.name) == 0:
            return None, {}, "Screenshot file is empty or copy failed"
        
        return temp_screenshot.name, selected, ""
        
    except Exception as e:
        logger.error(f"Error finding screenshot: {e}", exc_info=True)
        return None, {}, f"Error finding screenshot: {e}"


def verify_screenshot_comprehensive(
    screenshot_path: str, 
    screenshot_info: Dict,
    task_start_time: float
) -> Dict[str, Any]:
    """
    Comprehensive verification of screenshot with multiple criteria.
    
    Args:
        screenshot_path: Local path to screenshot file
        screenshot_info: Metadata about the screenshot
        task_start_time: Task start timestamp
        
    Returns:
        Verification result dictionary
    """
    # Expected dimensions for iPhone SE
    EXPECTED_WIDTH = 375
    EXPECTED_HEIGHT = 667
    DIMENSION_TOLERANCE = 5  # ±5 pixels
    
    criteria_results = {}
    feedback_parts = []
    
    # Criterion 1: File exists and is valid image
    try:
        img = Image.open(screenshot_path)
        criteria_results['valid_image'] = True
        feedback_parts.append(f"✓ Valid image file: {screenshot_info['filename']}")
    except Exception as e:
        criteria_results['valid_image'] = False
        feedback_parts.append(f"✗ Invalid image file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts)
        }
    
    # Criterion 2: Correct dimensions (375x667 ±5px)
    actual_width, actual_height = img.size
    width_diff = abs(actual_width - EXPECTED_WIDTH)
    height_diff = abs(actual_height - EXPECTED_HEIGHT)
    
    dimensions_match = (width_diff <= DIMENSION_TOLERANCE and height_diff <= DIMENSION_TOLERANCE)
    criteria_results['correct_dimensions'] = dimensions_match
    
    if dimensions_match:
        feedback_parts.append(
            f"✓ Correct dimensions: {actual_width}x{actual_height} "
            f"(expected {EXPECTED_WIDTH}x{EXPECTED_HEIGHT})"
        )
    else:
        feedback_parts.append(
            f"✗ Incorrect dimensions: {actual_width}x{actual_height} "
            f"(expected {EXPECTED_WIDTH}x{EXPECTED_HEIGHT} ±{DIMENSION_TOLERANCE}px)"
        )
    
    # Criterion 3: Created during task execution
    file_mtime = screenshot_info.get('mtime', time.time())
    time_since_start = file_mtime - task_start_time
    created_during_task = 0 <= time_since_start <= 300  # Within 5 minutes after start
    
    criteria_results['created_during_task'] = created_during_task
    
    if created_during_task:
        feedback_parts.append(
            f"✓ Created during task execution ({int(time_since_start)}s after start)"
        )
    else:
        feedback_parts.append(
            f"⚠ Unusual creation time ({int(time_since_start)}s after task start)"
        )
    
    # Criterion 4: Image has content (not blank)
    img_array = np.array(img.convert('RGB'))
    color_std = np.std(img_array)
    
    has_content = color_std > 5  # Standard deviation > 5 indicates variation
    criteria_results['has_content'] = has_content
    
    if has_content:
        feedback_parts.append(f"✓ Image has content (color variation: {color_std:.2f})")
    else:
        feedback_parts.append(f"✗ Image appears blank or nearly uniform (variation: {color_std:.2f})")
    
    # Criterion 5: Reasonable file size
    file_size = os.path.getsize(screenshot_path)
    reasonable_size = 1024 < file_size < 10 * 1024 * 1024  # Between 1KB and 10MB
    criteria_results['reasonable_size'] = reasonable_size
    
    if reasonable_size:
        feedback_parts.append(f"✓ Reasonable file size: {file_size / 1024:.1f} KB")
    else:
        feedback_parts.append(f"⚠ Unusual file size: {file_size / 1024:.1f} KB")
    
    # Calculate final score
    criteria_met = sum([
        criteria_results['valid_image'],
        criteria_results['correct_dimensions'],
        criteria_results['created_during_task'],
        criteria_results['has_content'],
        criteria_results['reasonable_size']
    ])
    
    score = int((criteria_met / 5) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (80%)
    
    # Build final feedback
    feedback_parts.append("")
    feedback_parts.append("=" * 60)
    feedback_parts.append(f"Criteria met: {criteria_met}/5")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if not passed:
        feedback_parts.append("")
        feedback_parts.append("To pass this task:")
        if not criteria_results['correct_dimensions']:
            feedback_parts.append("  • Ensure Device Mode is set to iPhone SE (375x667)")
        if not criteria_results['has_content']:
            feedback_parts.append("  • Verify the webpage loaded before capturing screenshot")
        if not criteria_results['created_during_task']:
            feedback_parts.append("  • Capture a new screenshot during the task execution")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "filename": screenshot_info['filename'],
            "dimensions": f"{actual_width}x{actual_height}",
            "expected_dimensions": f"{EXPECTED_WIDTH}x{EXPECTED_HEIGHT}",
            "file_size_kb": round(file_size / 1024, 1),
            "criteria_met": criteria_met,
            "criteria_results": criteria_results
        }
    }


def cleanup_temp_file(file_path: str):
    """Clean up temporary file."""
    try:
        if file_path and os.path.exists(file_path):
            os.unlink(file_path)
    except Exception as e:
        logger.warning(f"Could not clean up temp file: {e}")
