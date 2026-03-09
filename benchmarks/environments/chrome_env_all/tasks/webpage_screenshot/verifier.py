#!/usr/bin/env python3
"""
Verifier for Chrome Webpage Screenshot Task (webpage_screenshot@1)
Task: Capture a screenshot of a webpage using Chrome's built-in functionality

Verification Strategy:
- Search Downloads folder for PNG files created during task execution
- Validate file timing (created within task timeframe)
- Check PNG format integrity
- Verify dimensions are appropriate for browser viewport
- Validate file size indicates substantial content
- Analyze pixel data to ensure non-blank screenshot
"""

import logging
import sys
import os
import tempfile
import time
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
    Main verification function for webpage_screenshot@1.
    
    Verifies that a webpage screenshot was successfully captured and saved.
    
    Criteria (5 total, need 4+ to pass at 75%):
    1. PNG file exists in Downloads with recent timestamp
    2. File is valid PNG format and can be loaded
    3. Image dimensions are appropriate for browser viewport (800-1920 x 600-1200)
    4. File size indicates substantial content (≥10KB, ≤5MB)
    5. Image contains varied pixel data (not blank/solid color)
    
    Args:
        traj: Trajectory data (not used for this task)
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
            "feedback": "copy_from_env function not available in environment"
        }

    try:
        # Get task timing information
        task_start_time, task_end_time = get_task_timeframe(copy_from_env, task_info)
        logger.info(f"Task timeframe: {task_start_time} to {task_end_time} ({task_end_time - task_start_time:.0f}s duration)")
        
        # Find screenshot file
        screenshot_path, screenshot_name, error = find_screenshot_file(
            copy_from_env, 
            task_start_time, 
            task_end_time
        )
        
        if not screenshot_path:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No screenshot found: {error}",
                "details": {
                    "error": error,
                    "task_start": task_start_time,
                    "task_end": task_end_time
                }
            }
        
        # Verify screenshot meets criteria
        result = verify_screenshot_quality(
            screenshot_path,
            screenshot_name,
            task_start_time,
            task_end_time
        )
        
        # Cleanup temporary file
        try:
            if screenshot_path and os.path.exists(screenshot_path):
                os.unlink(screenshot_path)
        except Exception as e:
            logger.warning(f"Could not cleanup temp file: {e}")
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def get_task_timeframe(copy_from_env, task_info):
    """
    Get task start and end timestamps for file timing validation.
    
    Returns:
        Tuple of (start_time, end_time) as unix timestamps
    """
    current_time = time.time()
    
    # Try to get recorded start time
    try:
        temp_start = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_start.close()
        copy_from_env("/tmp/screenshot_task_start_time.txt", temp_start.name)
        
        with open(temp_start.name, 'r') as f:
            start_time = float(f.read().strip())
        os.unlink(temp_start.name)
        logger.info(f"Retrieved recorded start time: {start_time}")
    except Exception as e:
        logger.warning(f"Could not get start time, using fallback: {e}")
        # Fallback: assume task started 120 seconds ago
        start_time = current_time - 120
    
    # Try to get recorded end time
    try:
        temp_end = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_end.close()
        copy_from_env("/tmp/screenshot_task_end_time.txt", temp_end.name)
        
        with open(temp_end.name, 'r') as f:
            end_time = float(f.read().strip())
        os.unlink(temp_end.name)
        logger.info(f"Retrieved recorded end time: {end_time}")
    except Exception as e:
        logger.warning(f"Could not get end time, using current time: {e}")
        end_time = current_time
    
    # Add buffer for timing tolerance
    start_time -= 10  # 10 second buffer before
    end_time += 10    # 10 second buffer after
    
    return start_time, end_time


def find_screenshot_file(copy_from_env, start_time, end_time):
    """
    Find and copy screenshot file from container Downloads folder.
    
    Args:
        copy_from_env: Function to copy files from container
        start_time: Task start timestamp
        end_time: Task end timestamp
        
    Returns:
        Tuple of (local_path, filename, error_message)
    """
    # Try to get the latest screenshot name
    screenshot_name = None
    try:
        temp_name = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_name.close()
        copy_from_env("/tmp/latest_screenshot_name.txt", temp_name.name)
        
        with open(temp_name.name, 'r') as f:
            screenshot_name = f.read().strip()
        os.unlink(temp_name.name)
        
        if screenshot_name == "none":
            return None, None, "No screenshot file was found in Downloads folder during export"
        
        logger.info(f"Export script found screenshot: {screenshot_name}")
        
    except Exception as e:
        logger.warning(f"Could not read screenshot name: {e}")
    
    # Try multiple possible locations for the screenshot
    possible_paths = [
        "/tmp/latest_screenshot.png",  # Copied by export script
    ]
    
    # If we have a specific name, try direct path
    if screenshot_name and screenshot_name != "none":
        possible_paths.extend([
            f"/home/ga/Downloads/{screenshot_name}",
            f"/tmp/{screenshot_name}",
        ])
    
    # Also try common Chrome screenshot naming patterns
    possible_patterns = [
        "/home/ga/Downloads/Screenshot*.png",
        "/home/ga/Downloads/screenshot*.png",
    ]
    
    temp_file = None
    for container_path in possible_paths:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_file.close()
            
            logger.info(f"Trying to copy from: {container_path}")
            copy_from_env(container_path, temp_file.name)
            
            # Check if file has content
            file_size = Path(temp_file.name).stat().st_size
            if file_size > 0:
                logger.info(f"✓ Successfully copied screenshot from {container_path} ({file_size} bytes)")
                final_name = screenshot_name if screenshot_name else os.path.basename(container_path)
                return temp_file.name, final_name, ""
            else:
                os.unlink(temp_file.name)
                
        except Exception as e:
            logger.debug(f"Could not copy from {container_path}: {e}")
            if temp_file and os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
            continue
    
    # If direct paths failed, try to get file list and find recent PNG
    try:
        temp_list = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_list.close()
        copy_from_env("/tmp/screenshot_files_list.txt", temp_list.name)
        
        with open(temp_list.name, 'r') as f:
            lines = f.readlines()
        os.unlink(temp_list.name)
        
        # Parse file list: timestamp path size
        for line in lines:
            parts = line.strip().split()
            if len(parts) >= 3:
                file_timestamp = float(parts[0])
                file_path = parts[1]
                
                # Check if file was created during task timeframe
                if start_time <= file_timestamp <= end_time:
                    logger.info(f"Found candidate file: {file_path} (timestamp: {file_timestamp})")
                    
                    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                    temp_file.close()
                    
                    try:
                        copy_from_env(file_path, temp_file.name)
                        file_size = Path(temp_file.name).stat().st_size
                        if file_size > 0:
                            logger.info(f"✓ Successfully copied screenshot from file list")
                            return temp_file.name, os.path.basename(file_path), ""
                    except Exception as e:
                        logger.debug(f"Could not copy {file_path}: {e}")
                        if os.path.exists(temp_file.name):
                            os.unlink(temp_file.name)
                        continue
                        
    except Exception as e:
        logger.warning(f"Could not process file list: {e}")
    
    return None, None, "Screenshot file not found in any expected location or within task timeframe"


def verify_screenshot_quality(screenshot_path, screenshot_name, start_time, end_time):
    """
    Verify screenshot meets quality criteria.
    
    Args:
        screenshot_path: Local path to screenshot file
        screenshot_name: Original filename
        start_time: Task start timestamp
        end_time: Task end timestamp
        
    Returns:
        Dict with verification results
    """
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: File exists (already confirmed)
    criteria_met += 1
    feedback_parts.append(f"✓ Screenshot file found: {screenshot_name}")
    
    # Criterion 2: Valid PNG format
    if not HAS_PIL:
        feedback_parts.append("⚠ PIL not available, skipping format validation")
        criteria_met += 0.5  # Partial credit
    else:
        try:
            img = Image.open(screenshot_path)
            img.verify()
            criteria_met += 1
            feedback_parts.append(f"✓ Valid PNG format")
        except Exception as e:
            feedback_parts.append(f"✗ PNG validation failed: {e}")
    
    # Criterion 3: Reasonable dimensions
    if not HAS_PIL:
        feedback_parts.append("⚠ PIL not available, skipping dimension check")
        criteria_met += 0.5  # Partial credit
    else:
        try:
            img = Image.open(screenshot_path)  # Re-open after verify
            width, height = img.size
            
            # Expected viewport dimensions
            MIN_WIDTH, MAX_WIDTH = 800, 1920
            MIN_HEIGHT, MAX_HEIGHT = 600, 1200
            
            if MIN_WIDTH <= width <= MAX_WIDTH and MIN_HEIGHT <= height <= MAX_HEIGHT:
                criteria_met += 1
                feedback_parts.append(f"✓ Appropriate dimensions: {width}x{height}px")
            else:
                feedback_parts.append(f"⚠ Unusual dimensions: {width}x{height}px (expected {MIN_WIDTH}-{MAX_WIDTH} x {MIN_HEIGHT}-{MAX_HEIGHT})")
                if width >= MIN_WIDTH and height >= MIN_HEIGHT:
                    criteria_met += 0.7  # Partial credit if at least minimum size
        except Exception as e:
            feedback_parts.append(f"✗ Could not check dimensions: {e}")
    
    # Criterion 4: Adequate file size
    try:
        file_size = os.path.getsize(screenshot_path)
        size_kb = file_size / 1024
        size_mb = file_size / (1024 * 1024)
        
        MIN_SIZE = 10_000  # 10KB
        MAX_SIZE = 5_000_000  # 5MB
        
        if MIN_SIZE <= file_size <= MAX_SIZE:
            criteria_met += 1
            if size_mb >= 1:
                feedback_parts.append(f"✓ Adequate file size: {size_mb:.2f}MB")
            else:
                feedback_parts.append(f"✓ Adequate file size: {size_kb:.1f}KB")
        else:
            if file_size < MIN_SIZE:
                feedback_parts.append(f"✗ File too small: {size_kb:.1f}KB (minimum 10KB)")
            else:
                feedback_parts.append(f"✗ File too large: {size_mb:.2f}MB (maximum 5MB)")
                
    except Exception as e:
        feedback_parts.append(f"✗ Could not check file size: {e}")
    
    # Criterion 5: Content present (not blank)
    if not HAS_PIL:
        feedback_parts.append("⚠ PIL not available, skipping content analysis")
        criteria_met += 0.5  # Partial credit
    else:
        try:
            img = Image.open(screenshot_path)
            img_array = np.array(img.convert('RGB'))
            
            # Calculate pixel statistics
            pixel_mean = np.mean(img_array)
            pixel_std = np.std(img_array)
            
            # Check for variety in pixel values
            if pixel_std > 10:  # Standard deviation indicates variety
                criteria_met += 1
                feedback_parts.append(f"✓ Image contains varied content (σ={pixel_std:.1f})")
            else:
                feedback_parts.append(f"✗ Image appears blank or uniform (σ={pixel_std:.1f})")
                
            # Additional check: not all white or all black
            if 240 <= pixel_mean <= 255:
                feedback_parts.append("⚠ Image is very bright (possibly blank white)")
                criteria_met -= 0.3
            elif pixel_mean <= 15:
                feedback_parts.append("⚠ Image is very dark (possibly blank black)")
                criteria_met -= 0.3
                
        except Exception as e:
            feedback_parts.append(f"✗ Could not analyze content: {e}")
    
    # Ensure criteria_met doesn't go negative or exceed total
    criteria_met = max(0, min(criteria_met, total_criteria))
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need at least 4/5 criteria (75%)
    
    # Build final feedback
    summary = f"Screenshot verification: {criteria_met:.1f}/{total_criteria} criteria met\n"
    summary += "\n".join(feedback_parts)
    summary += f"\n\n{'='*50}"
    summary += f"\nFinal score: {score}%"
    summary += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PIL:
        summary += "\n\n⚠ Note: PIL/Pillow library not available, some checks had limited functionality"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={criteria_met:.1f}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": summary,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "filename": screenshot_name
        }
    }
