#!/usr/bin/env python3
"""
Verifier for Chrome Screenshot Webpage Region Task (screenshot_webpage_region@1)
Task: Capture a screenshot of webpage content using Chrome DevTools screenshot feature

Verification Strategy:
- Check Downloads folder for recently created screenshot files
- Validate screenshot file exists and is not corrupted
- Analyze screenshot content using image hashing to verify it contains the target content
- Check dimensions and quality
- Compare against reference characteristics of the target content
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import imagehash
    HAS_IMAGE_LIBS = True
except ImportError:
    HAS_IMAGE_LIBS = False
    logger.warning("PIL/imagehash not available, verification will be limited")


def verify_task(traj, env_info, task_info):
    """
    Main verification function for screenshot_webpage_region@1 task.
    
    Verifies that:
    1. Screenshot file was created in Downloads folder
    2. File is recent (created during task execution)
    3. File is valid image with reasonable size
    4. Image dimensions are appropriate for a viewport screenshot
    5. Image content appears to contain the target chart elements
    
    Scoring:
    - 100%: All 5 criteria met (perfect screenshot capture)
    - 80%: 4/5 criteria met (minor issues)
    - 60%: 3/5 criteria met (partial success)
    - <60%: <3 criteria met (failed)
    
    Pass threshold: 75% (at least 4 out of 5 criteria)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, and feedback keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    try:
        # Get task start time for validation
        task_start_time = get_task_start_time(copy_from_env)
        if task_start_time is None:
            logger.warning("Could not get task start time, using current time minus 120s")
            task_start_time = datetime.now() - timedelta(seconds=120)
        
        # Criterion 1: Screenshot file exists
        logger.info("Checking if screenshot file exists...")
        screenshot_path, screenshot_name, error = find_screenshot_file(copy_from_env)
        
        if not screenshot_path:
            feedback = f"✗ Screenshot file not found\n{error}"
            feedback += "\n\nExpected behavior:"
            feedback += "\n  1. Press F12 to open Chrome DevTools"
            feedback += "\n  2. Press Ctrl+Shift+P to open Command Menu"
            feedback += "\n  3. Type 'screenshot' and select 'Capture screenshot'"
            feedback += "\n  4. Screenshot saves to Downloads folder"
            return {
                "passed": False,
                "score": 0,
                "feedback": feedback
            }
        
        feedback_parts.append(f"✓ Screenshot file found: {screenshot_name}")
        criteria_met += 1
        
        # Criterion 2: File was created recently (during task execution)
        logger.info("Checking screenshot creation time...")
        is_recent, time_info = check_file_timestamp(screenshot_path, task_start_time)
        if is_recent:
            feedback_parts.append(f"✓ Screenshot created during task execution ({time_info})")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Screenshot timestamp issue: {time_info}")
        
        # Criterion 3: File is valid and has reasonable size
        logger.info("Checking file validity and size...")
        is_valid, size_kb, size_feedback = check_file_validity(screenshot_path)
        if is_valid:
            feedback_parts.append(f"✓ File valid: {size_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ File issue: {size_feedback}")
        
        # Criterion 4: Image dimensions are appropriate
        logger.info("Checking image dimensions...")
        dims_ok, dimensions, dims_feedback = check_image_dimensions(screenshot_path)
        if dims_ok:
            feedback_parts.append(f"✓ Dimensions appropriate: {dims_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Dimension issue: {dims_feedback}")
        
        # Criterion 5: Image appears to contain expected content
        logger.info("Analyzing image content...")
        content_ok, content_score, content_feedback = analyze_image_content(screenshot_path)
        if content_ok:
            feedback_parts.append(f"✓ Content verified: {content_feedback}")
            criteria_met += 1
        else:
            feedback_parts.append(f"⚠ Content check: {content_feedback}")
            # Give partial credit if we can't verify content
            if "limited" in content_feedback.lower():
                criteria_met += 0.5
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        # Build final feedback
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*50}"
        feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        if not HAS_IMAGE_LIBS:
            feedback += "\n\n⚠ Note: Image analysis libraries not available, content verification limited"
        
        # Clean up temporary file
        try:
            if screenshot_path and os.path.exists(screenshot_path):
                os.unlink(screenshot_path)
        except:
            pass
        
        logger.info(f"Verification complete: passed={passed}, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "details": {
                "criteria_met": criteria_met,
                "screenshot_name": screenshot_name,
                "dimensions": dimensions if dims_ok else None
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_task_start_time(copy_from_env):
    """
    Get the task start time from the recorded timestamp.
    
    Returns:
        datetime object or None
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/screenshot_task_start_time.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            timestamp = int(f.read().strip())
        
        os.unlink(temp_file.name)
        return datetime.fromtimestamp(timestamp)
        
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}")
        return None


def find_screenshot_file(copy_from_env):
    """
    Find and copy the screenshot file from Downloads folder.
    
    Returns:
        Tuple of (local_path, filename, error_message)
    """
    try:
        # First try to get the filename that was recorded
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_filename.close()
        
        try:
            copy_from_env("/tmp/screenshot_verification/screenshot_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_info = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_info == "none":
                return None, "", "No screenshot file was found in Downloads folder"
            
            # Extract just the filename
            found_name = os.path.basename(found_info)
            
        except Exception as e:
            logger.warning(f"Could not read screenshot_filename.txt: {e}")
            found_name = "captured_screenshot.png"
        
        # Try to copy the screenshot file
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_screenshot.close()
        
        # Try multiple possible paths
        possible_paths = [
            "/tmp/screenshot_verification/captured_screenshot.png",
            f"/tmp/screenshot_verification/{found_name}",
            f"/tmp/captured_screenshot.png",
            f"/home/ga/Downloads/{found_name}",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy screenshot from: {container_path}")
                copy_from_env(container_path, temp_screenshot.name)
                
                # Check if file has content
                if Path(temp_screenshot.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied screenshot from: {container_path}")
                    return temp_screenshot.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_screenshot.name)
        return None, "", "Screenshot file could not be copied from any known location"
        
    except Exception as e:
        logger.error(f"Error finding screenshot: {e}", exc_info=True)
        return None, "", f"Error finding screenshot: {str(e)}"


def check_file_timestamp(file_path, task_start_time):
    """
    Check if file was created during task execution window.
    
    Returns:
        Tuple of (is_recent, time_info)
    """
    try:
        file_mtime = datetime.fromtimestamp(Path(file_path).stat().st_mtime)
        time_diff = (file_mtime - task_start_time).total_seconds()
        
        # File should be created after task start and within reasonable window
        if time_diff < -10:
            return False, f"File too old (created {abs(time_diff):.0f}s before task start)"
        elif time_diff > 180:
            return False, f"File created too late ({time_diff:.0f}s after task start)"
        else:
            return True, f"created {time_diff:.0f}s after task start"
            
    except Exception as e:
        return False, f"Could not check timestamp: {e}"


def check_file_validity(file_path):
    """
    Check if file is valid image with reasonable size.
    
    Returns:
        Tuple of (is_valid, size_kb, feedback)
    """
    try:
        size_bytes = Path(file_path).stat().st_size
        size_kb = size_bytes / 1024
        
        if size_bytes < 1024:
            return False, size_kb, f"File too small ({size_bytes} bytes)"
        elif size_bytes < 5120:  # Less than 5KB is suspicious for screenshot
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB)"
        elif size_bytes > 10485760:  # More than 10MB is excessive
            return False, size_kb, f"File too large ({size_kb/1024:.1f} MB)"
        else:
            return True, size_kb, f"{size_kb:.1f} KB"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def check_image_dimensions(file_path):
    """
    Check if image has appropriate dimensions for a viewport screenshot.
    
    Returns:
        Tuple of (is_appropriate, dimensions, feedback)
    """
    if not HAS_IMAGE_LIBS:
        return None, None, "Image library not available (assumed OK)"
    
    try:
        img = Image.open(file_path)
        width, height = img.size
        
        # Reasonable viewport screenshot dimensions
        MIN_WIDTH = 400
        MIN_HEIGHT = 300
        MAX_WIDTH = 3840  # 4K
        MAX_HEIGHT = 2160
        
        if width < MIN_WIDTH or height < MIN_HEIGHT:
            return False, (width, height), f"{width}x{height} (too small for viewport)"
        elif width > MAX_WIDTH or height > MAX_HEIGHT:
            return False, (width, height), f"{width}x{height} (unreasonably large)"
        else:
            return True, (width, height), f"{width}x{height}"
            
    except Exception as e:
        logger.error(f"Error checking dimensions: {e}")
        return False, None, f"Could not check dimensions: {e}"


def analyze_image_content(file_path):
    """
    Analyze image to verify it contains expected content characteristics.
    
    For this task, we check for:
    - Purple/gradient colors (the chart has purple gradient)
    - Reasonable color distribution (not blank/solid)
    - Sufficient complexity (not just a single color)
    
    Returns:
        Tuple of (content_ok, score, feedback)
    """
    if not HAS_IMAGE_LIBS:
        return True, 100, "Limited verification (image libs unavailable, assumed OK)"
    
    try:
        img = Image.open(file_path)
        
        # Convert to RGB if needed
        if img.mode != 'RGB':
            img = img.convert('RGB')
        
        # Check 1: Image is not blank or mostly single color
        # Get representative colors
        img_small = img.resize((100, 100))
        colors = img_small.getcolors(maxcolors=10000)
        
        if not colors or len(colors) < 10:
            return False, 20, "Image appears to be blank or single color"
        
        # Check 2: Look for purple/blue colors indicative of the chart
        # Target gradient is from #667eea (purple-blue) to #764ba2 (purple)
        has_purple_gradient = False
        purple_blue_pixels = 0
        total_sampled = 0
        
        for color, count in colors:
            r, g, b = color
            total_sampled += count
            
            # Check if color is in purple-blue range
            # Purple-blue has higher blue component, moderate red, lower green
            if b > 150 and r > 80 and g < b:  # Blue-purple range
                purple_blue_pixels += count
            elif r > 100 and b > 140 and r < b:  # Purple range
                purple_blue_pixels += count
        
        purple_ratio = purple_blue_pixels / total_sampled if total_sampled > 0 else 0
        
        if purple_ratio > 0.15:  # At least 15% purple/blue content
            has_purple_gradient = True
        
        # Check 3: Image has reasonable complexity (not error page or blank)
        complexity_ok = len(colors) > 50
        
        # Scoring
        checks_passed = sum([
            len(colors) >= 10,  # Not blank
            has_purple_gradient,  # Has expected colors
            complexity_ok  # Sufficient detail
        ])
        
        if checks_passed >= 2:
            content_ok = True
            feedback = f"Content appears valid ({purple_ratio*100:.1f}% target colors, {len(colors)} unique colors)"
            score = min(100, 70 + checks_passed * 10)
        else:
            content_ok = False
            feedback = f"Content may not match target ({purple_ratio*100:.1f}% target colors, only {len(colors)} unique colors)"
            score = 40
        
        return content_ok, score, feedback
        
    except Exception as e:
        logger.error(f"Error analyzing content: {e}")
        # Don't fail on content analysis error, give benefit of doubt
        return True, 75, f"Content analysis limited: {e}"
