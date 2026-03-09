#!/usr/bin/env python3
"""
Verifier for Chrome Full-Page Screenshot Task (full_page_screenshot@1)
Task: Capture a full-page screenshot using Chrome DevTools

Verification Strategy:
- Check if screenshot file exists in Downloads folder
- Verify file was created during task execution window
- Validate PNG image format and integrity
- Check image dimensions (height > 1200px indicates full-page capture)
- Verify reasonable file size (50KB - 20MB)
- Check for actual content (not blank image)

Scoring:
- 100%: All 6 criteria met
- 75-99%: 5/6 criteria met (passing)
- 50-74%: 4/6 criteria met
- <50%: <4 criteria met (failing)

Pass threshold: 75% (need at least 5 out of 6 criteria)
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    logger.warning("PIL/Pillow not available, image analysis will be limited")


def verify_task(traj, env_info, task_info):
    """
    Main verification function for full_page_screenshot@1.
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback, details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available in environment"
        }

    try:
        # Get task timing information
        task_start, task_end = get_task_timing(copy_from_env)
        logger.info(f"Task window: {task_start} to {task_end}")
        
        # Find and retrieve screenshot
        screenshot_path, screenshot_name, error = find_screenshot(copy_from_env)
        
        if screenshot_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"✗ Screenshot not found\n{error}\n\nHint: Use DevTools (F12), then Ctrl+Shift+P, search 'screenshot', select 'Capture full size screenshot'"
            }
        
        logger.info(f"Found screenshot: {screenshot_name}")
        
        # Perform verification checks
        result = verify_screenshot(screenshot_path, screenshot_name, task_start, task_end)
        
        # Clean up temp file
        try:
            if screenshot_path and os.path.exists(screenshot_path):
                os.unlink(screenshot_path)
        except:
            pass
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_task_timing(copy_from_env):
    """Get task start and end times from container."""
    try:
        # Get start time
        temp_start = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        temp_start.close()
        copy_from_env("/tmp/screenshot_verification/task_start_time.txt", temp_start.name)
        with open(temp_start.name, 'r') as f:
            task_start = int(f.read().strip())
        os.unlink(temp_start.name)
        
        # Get end time
        temp_end = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        temp_end.close()
        copy_from_env("/tmp/screenshot_verification/task_end_time.txt", temp_end.name)
        with open(temp_end.name, 'r') as f:
            task_end = int(f.read().strip())
        os.unlink(temp_end.name)
        
        return task_start, task_end
        
    except Exception as e:
        logger.warning(f"Could not get task timing: {e}, using wide window")
        import time
        current = int(time.time())
        return current - 300, current + 60


def find_screenshot(copy_from_env):
    """Find and copy the screenshot file from container."""
    try:
        # Check if screenshot was found
        temp_check = tempfile.NamedTemporaryFile(delete=False, mode='w+')
        temp_check.close()
        
        try:
            copy_from_env("/tmp/screenshot_verification/screenshot_found.txt", temp_check.name)
            with open(temp_check.name, 'r') as f:
                found = f.read().strip()
            os.unlink(temp_check.name)
            
            if found == "none":
                return None, "", "No PNG files found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not check screenshot_found.txt: {e}")
        
        # Try to copy the screenshot
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_screenshot.close()
        
        # Try multiple possible locations
        possible_paths = [
            "/tmp/screenshot_verification/captured_screenshot.png",
        ]
        
        # Try to get path from export script
        try:
            temp_path_file = tempfile.NamedTemporaryFile(delete=False, mode='w+')
            temp_path_file.close()
            copy_from_env("/tmp/screenshot_verification/screenshot_path.txt", temp_path_file.name)
            with open(temp_path_file.name, 'r') as f:
                container_path = f.read().strip()
            os.unlink(temp_path_file.name)
            if container_path:
                possible_paths.insert(0, container_path)
        except:
            pass
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy screenshot from: {container_path}")
                copy_from_env(container_path, temp_screenshot.name)
                
                if Path(temp_screenshot.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied screenshot")
                    filename = os.path.basename(container_path)
                    return temp_screenshot.name, filename, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        os.unlink(temp_screenshot.name)
        return None, "", "Screenshot file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding screenshot: {e}")
        return None, "", f"Error finding screenshot: {str(e)}"


def verify_screenshot(screenshot_path, screenshot_name, task_start, task_end):
    """Perform multi-criteria verification of the screenshot."""
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    details = {}
    
    # Criterion 1: File exists
    criteria_met += 1
    feedback_parts.append(f"✓ Screenshot file found: {screenshot_name}")
    details['file_found'] = True
    details['filename'] = screenshot_name
    
    # Criterion 2: File created during task window
    try:
        file_mtime = os.path.getmtime(screenshot_path)
        details['file_mtime'] = file_mtime
        
        if task_start <= file_mtime <= task_end + 60:  # 60s grace period
            criteria_met += 1
            feedback_parts.append("✓ File created during task execution")
            details['timing_valid'] = True
        else:
            feedback_parts.append(f"✗ File timestamp outside task window")
            details['timing_valid'] = False
    except Exception as e:
        feedback_parts.append(f"⚠ Could not check file timestamp: {e}")
        details['timing_valid'] = None
    
    # Criterion 3: Valid PNG image
    if not HAS_PIL:
        feedback_parts.append("⚠ PIL not available, skipping image analysis")
        criteria_met += 0.3
        details['valid_image'] = None
    else:
        try:
            img = Image.open(screenshot_path)
            width, height = img.size
            format_name = img.format
            
            if format_name == 'PNG':
                criteria_met += 1
                feedback_parts.append(f"✓ Valid PNG image: {width}×{height}px")
                details['valid_image'] = True
                details['dimensions'] = {'width': width, 'height': height}
            else:
                feedback_parts.append(f"✗ Wrong format: {format_name} (expected PNG)")
                details['valid_image'] = False
        except Exception as e:
            feedback_parts.append(f"✗ Invalid image file: {e}")
            details['valid_image'] = False
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": "\n".join(feedback_parts),
                "details": details
            }
    
    # Criterion 4: Full-page height (>1200px)
    if HAS_PIL and details.get('valid_image'):
        height = details['dimensions']['height']
        
        if height > 1200:
            criteria_met += 1
            feedback_parts.append(f"✓ Full-page height detected: {height}px")
            details['full_page_height'] = True
        else:
            feedback_parts.append(f"✗ Height {height}px suggests viewport-only capture (expected >1200px)")
            details['full_page_height'] = False
    
    # Criterion 5: Reasonable file size
    try:
        file_size = os.path.getsize(screenshot_path)
        details['file_size_bytes'] = file_size
        
        if 50_000 < file_size < 20_000_000:
            criteria_met += 1
            file_size_kb = file_size / 1024
            feedback_parts.append(f"✓ File size reasonable: {file_size_kb:.1f} KB")
            details['file_size_ok'] = True
        else:
            file_size_kb = file_size / 1024
            feedback_parts.append(f"✗ File size issue: {file_size_kb:.1f} KB")
            details['file_size_ok'] = False
    except Exception as e:
        feedback_parts.append(f"⚠ Could not check file size: {e}")
        details['file_size_ok'] = None
    
    # Criterion 6: Content present (not blank)
    if HAS_PIL and details.get('valid_image'):
        try:
            img = Image.open(screenshot_path)
            img_array = np.array(img.convert('L'))
            pixel_std = np.std(img_array)
            
            details['pixel_variance'] = float(pixel_std)
            
            if pixel_std > 10:
                criteria_met += 1
                feedback_parts.append(f"✓ Content detected (pixel variance: {pixel_std:.1f})")
                details['content_present'] = True
            else:
                feedback_parts.append(f"✗ Image appears blank (variance: {pixel_std:.1f})")
                details['content_present'] = False
        except Exception as e:
            feedback_parts.append(f"⚠ Could not analyze content: {e}")
            details['content_present'] = None
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Add summary
    feedback_parts.append("")
    feedback_parts.append("=" * 50)
    feedback_parts.append(f"Criteria met: {criteria_met:.1f}/{total_criteria}")
    feedback_parts.append(f"Final score: {score}%")
    feedback_parts.append(f"Result: {'PASSED ✓' if passed else 'FAILED ✗'}")
    
    if not HAS_PIL:
        feedback_parts.append("\n⚠ Note: PIL/Pillow unavailable, some checks limited")
    
    if passed:
        feedback_parts.append("\n✅ Full-page screenshot successfully captured!")
    else:
        feedback_parts.append("\n❌ Screenshot incomplete or incorrect")
        if not details.get('full_page_height'):
            feedback_parts.append("Hint: Open DevTools (F12), press Ctrl+Shift+P, type 'screenshot',")
            feedback_parts.append("      then select 'Capture full size screenshot' (not just 'Capture screenshot')")
    
    feedback = "\n".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }
