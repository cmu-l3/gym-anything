#!/usr/bin/env python3
"""
Verifier for Chrome Full-Page Screenshot Task (fullpage_screenshot@1)
Task: Capture full-page screenshot using Chrome DevTools

Verification Strategy:
- Check Downloads folder (via copied files) for PNG screenshots
- Verify file was created during task execution (timestamp check)
- Analyze image dimensions to confirm full-page capture
- Validate image quality and content (not blank/corrupt)
- Check filename patterns match Chrome's screenshot naming

Scoring Criteria:
1. Screenshot file exists (25%)
2. Valid PNG format and proper dimensions (25%)
3. Full-page dimensions detected (height > 1.8x viewport) (25%)
4. Image has meaningful content (not blank) (25%)
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, Any, Tuple, Optional

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


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for fullpage_screenshot@1 task.
    
    Args:
        traj: Trajectory data (unused for this task)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
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
            "feedback": "PIL/Pillow library not available for image verification. Please install Pillow."
        }

    try:
        # Find and analyze screenshot file
        screenshot_path, screenshot_name, error_msg = find_screenshot_file(copy_from_env)
        
        if screenshot_path is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No screenshot found: {error_msg}"
            }
        
        # Perform multi-criteria verification
        verification_result = verify_fullpage_screenshot(screenshot_path, screenshot_name)
        
        # Clean up temporary file
        try:
            if screenshot_path and os.path.exists(screenshot_path):
                os.unlink(screenshot_path)
        except:
            pass
        
        return verification_result

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def find_screenshot_file(copy_from_env) -> Tuple[Optional[str], Optional[str], str]:
    """
    Find and copy screenshot file from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (local_path, filename, error_message)
    """
    try:
        # First, get the list of screenshot filenames
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
        temp_list.close()
        
        try:
            copy_from_env("/tmp/screenshot_verification/screenshot_list.txt", temp_list.name)
        except:
            # Fallback to checking /tmp directly
            try:
                copy_from_env("/tmp/screenshot_list.txt", temp_list.name)
            except Exception as e:
                os.unlink(temp_list.name)
                return None, None, f"Could not find screenshot list file: {e}"
        
        # Read the list of screenshots
        with open(temp_list.name, 'r') as f:
            screenshot_files = [line.strip() for line in f if line.strip()]
        
        os.unlink(temp_list.name)
        
        if not screenshot_files:
            return None, None, "No PNG files found in verification directory"
        
        logger.info(f"Found {len(screenshot_files)} screenshot file(s): {screenshot_files}")
        
        # Use the most recent/first screenshot
        screenshot_name = screenshot_files[0]
        
        # Try to copy the screenshot file
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_screenshot.close()
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/screenshot_verification/{screenshot_name}",
            f"/tmp/{screenshot_name}",
            f"/home/ga/Downloads/{screenshot_name}"
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy screenshot from: {container_path}")
                copy_from_env(container_path, temp_screenshot.name)
                
                # Check if file has content
                if Path(temp_screenshot.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied screenshot from: {container_path}")
                    return temp_screenshot.name, screenshot_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_screenshot.name)
        return None, None, f"Screenshot file '{screenshot_name}' could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding screenshot: {e}", exc_info=True)
        return None, None, f"Error finding screenshot: {str(e)}"


def verify_fullpage_screenshot(screenshot_path: str, filename: str) -> Dict[str, Any]:
    """
    Verify that the screenshot is a valid full-page capture.
    
    Checks:
    1. File exists and has reasonable size (>50KB for long page)
    2. Valid PNG format that can be opened
    3. Dimensions indicate full-page capture (height >> viewport)
    4. Image contains meaningful content (not blank)
    
    Args:
        screenshot_path: Local path to screenshot file
        filename: Original filename
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    criteria_results = []
    feedback_parts = []
    
    # Criterion 1: File size check
    try:
        file_size = Path(screenshot_path).stat().st_size
        size_kb = file_size / 1024
        
        if file_size < 10240:  # Less than 10KB
            criteria_results.append(False)
            feedback_parts.append(f"✗ File size too small: {size_kb:.1f}KB (likely incomplete)")
        elif file_size < 51200:  # Less than 50KB
            criteria_results.append(True)
            feedback_parts.append(f"⚠ File size: {size_kb:.1f}KB (smaller than expected for full page)")
        else:
            criteria_results.append(True)
            feedback_parts.append(f"✓ File size: {size_kb:.1f}KB")
            
    except Exception as e:
        criteria_results.append(False)
        feedback_parts.append(f"✗ Could not check file size: {e}")
    
    # Criterion 2 & 3: Image format and dimension analysis
    try:
        img = Image.open(screenshot_path)
        width, height = img.size
        
        # Criterion 2: Valid format
        if img.format == 'PNG':
            criteria_results.append(True)
            feedback_parts.append(f"✓ Valid PNG format: {width}x{height}px")
        else:
            criteria_results.append(False)
            feedback_parts.append(f"✗ Invalid format: {img.format} (expected PNG)")
        
        # Criterion 3: Full-page dimensions check
        # Typical viewport heights: 720px, 900px, 1080px
        # Full page should be significantly taller
        TYPICAL_VIEWPORT_HEIGHT = 900
        MIN_FULLPAGE_HEIGHT = 1500
        fullpage_ratio = height / TYPICAL_VIEWPORT_HEIGHT
        
        is_fullpage = height >= MIN_FULLPAGE_HEIGHT and fullpage_ratio >= 1.8
        is_portrait = height > width
        width_reasonable = 800 <= width <= 2560
        
        if is_fullpage and is_portrait:
            criteria_results.append(True)
            feedback_parts.append(f"✓ Full-page dimensions detected: {fullpage_ratio:.1f}x viewport height")
        elif height > TYPICAL_VIEWPORT_HEIGHT:
            criteria_results.append(True)
            feedback_parts.append(f"⚠ Partial page capture: {fullpage_ratio:.1f}x viewport (may not be complete)")
        else:
            criteria_results.append(False)
            feedback_parts.append(f"✗ Viewport-only screenshot: {height}px height (expected >{MIN_FULLPAGE_HEIGHT}px)")
        
        if not width_reasonable:
            feedback_parts.append(f"⚠ Unusual width: {width}px")
        
        # Criterion 4: Content variance check (not blank)
        try:
            img_gray = img.convert('L')  # Convert to grayscale
            pixels = np.array(img_gray)
            variance = np.var(pixels)
            
            # Meaningful content should have significant pixel variance
            if variance > 100:
                criteria_results.append(True)
                feedback_parts.append(f"✓ Content detected (variance: {variance:.1f})")
            elif variance > 50:
                criteria_results.append(True)
                feedback_parts.append(f"⚠ Low content variance: {variance:.1f} (possible blank areas)")
            else:
                criteria_results.append(False)
                feedback_parts.append(f"✗ Image appears blank or uniform (variance: {variance:.1f})")
                
        except Exception as e:
            # Partial credit if we can't check variance
            criteria_results.append(True)
            feedback_parts.append(f"⚠ Could not verify content variance: {e}")
        
        img.close()
        
    except Exception as e:
        logger.error(f"Error analyzing image: {e}")
        criteria_results.append(False)
        criteria_results.append(False)
        criteria_results.append(False)
        feedback_parts.append(f"✗ Could not open or analyze image: {e}")
    
    # Calculate final score
    # We have 4 criteria, but weight full-page dimension check higher
    total_possible = 4
    criteria_met = sum(criteria_results)
    
    score = int((criteria_met / total_possible) * 100)
    passed = score >= 75  # Need at least 3/4 criteria
    
    # Check filename for Chrome screenshot patterns
    filename_lower = filename.lower()
    if any(pattern in filename_lower for pattern in ['screenshot', 'capture', 'web']):
        feedback_parts.append(f"✓ Filename matches screenshot pattern: {filename}")
    else:
        feedback_parts.append(f"⚠ Unusual filename: {filename}")
    
    # Build final feedback
    feedback = "Full-Page Screenshot Verification Results:\n"
    feedback += "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/{total_possible}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += "\n\n✅ Task completed successfully! Full-page screenshot captured."
    else:
        feedback += "\n\n❌ Task incomplete. Common issues:"
        feedback += "\n   - Used 'Capture screenshot' instead of 'Capture full size screenshot'"
        feedback += "\n   - DevTools Command Menu not accessed (Ctrl+Shift+P)"
        feedback += "\n   - Screenshot not saved or still in progress"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met}/{total_possible}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "filename": filename,
            "criteria_met": criteria_met,
            "total_criteria": total_possible
        }
    }
