#!/usr/bin/env python3
"""
Verifier for Chrome DevTools Full Page Screenshot Task (devtools_full_screenshot@1)
Task: Use DevTools Command Palette to capture a full-page screenshot

Verification Strategy:
- Search Downloads folder for recent PNG files
- Verify file was created during task execution window
- Validate PNG format and image integrity
- Check dimensions indicate full-page capture (height > 1000px)
- Verify reasonable file size and content variance
"""

import logging
import sys
import os
import time
import tempfile
from pathlib import Path
from typing import Dict, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import image processing libraries
try:
    from PIL import Image
    import numpy as np
    HAS_PIL = True
except ImportError:
    logger.warning("PIL/Pillow not available, image analysis will be limited")
    HAS_PIL = False


def verify_task(traj, env_info, task_info) -> Dict:
    """
    Main verification function for devtools_full_screenshot@1.
    
    Verifies:
    1. Screenshot file exists in Downloads folder
    2. File was created during task execution timeframe
    3. File is a valid PNG image
    4. Image dimensions indicate full-page capture (height > 1000px)
    5. File size is reasonable and image contains valid content
    
    Scoring:
    - 100%: All 4 core criteria met
    - 75%: 3/4 criteria met (passing)
    - 50%: 2/4 criteria met
    - <50%: <2 criteria met (failing)
    
    Pass threshold: 75% (requires at least 3 out of 4 criteria)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    try:
        # Get task start time for recency check
        task_start_time = get_task_start_time(copy_from_env)
        
        # Find and retrieve screenshot file
        screenshot_info = find_screenshot_file(copy_from_env, task_start_time)
        
        if not screenshot_info['found']:
            return {
                "passed": False,
                "score": 0,
                "feedback": screenshot_info['error']
            }
        
        # Verify the screenshot meets all criteria
        result = verify_screenshot_quality(
            screenshot_info['local_path'],
            screenshot_info['filename'],
            screenshot_info['creation_time'],
            task_start_time
        )
        
        # Cleanup temporary file
        try:
            if screenshot_info['local_path'] and os.path.exists(screenshot_info['local_path']):
                os.unlink(screenshot_info['local_path'])
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


def get_task_start_time(copy_from_env) -> float:
    """
    Get the task start time from container.
    
    Returns:
        Unix timestamp of task start, or current time - 300s if not available
    """
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_file.close()
        
        copy_from_env("/tmp/task_start_time.txt", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            task_start = float(f.read().strip())
        
        os.unlink(temp_file.name)
        logger.info(f"Task start time: {task_start}")
        return task_start
        
    except Exception as e:
        logger.warning(f"Could not get task start time: {e}, using fallback")
        # Fallback: assume task started 5 minutes ago
        return time.time() - 300


def find_screenshot_file(copy_from_env, task_start_time: float) -> Dict:
    """
    Find and copy the most recent screenshot from Downloads folder.
    
    Args:
        copy_from_env: Function to copy files from container
        task_start_time: Unix timestamp when task started
        
    Returns:
        Dict with 'found', 'local_path', 'filename', 'creation_time', 'error'
    """
    try:
        # Get downloads manifest
        temp_manifest = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_manifest.close()
        
        try:
            copy_from_env("/tmp/downloads_manifest.txt", temp_manifest.name)
            
            with open(temp_manifest.name, 'r') as f:
                manifest_lines = f.readlines()
            
            os.unlink(temp_manifest.name)
            
            if not manifest_lines:
                return {
                    'found': False,
                    'error': "No PNG files found in Downloads folder"
                }
            
            # Parse manifest: format is "timestamp path size"
            candidates = []
            for line in manifest_lines:
                parts = line.strip().split(None, 2)
                if len(parts) >= 2:
                    timestamp = float(parts[0])
                    filepath = parts[1]
                    candidates.append((timestamp, filepath))
            
            if not candidates:
                return {
                    'found': False,
                    'error': "No valid PNG files in manifest"
                }
            
            # Get the most recent file created after task start
            recent_files = [
                (ts, path) for ts, path in candidates 
                if ts >= task_start_time
            ]
            
            if not recent_files:
                # Try with a more lenient time window (2 minutes before task start)
                recent_files = [
                    (ts, path) for ts, path in candidates 
                    if ts >= (task_start_time - 120)
                ]
            
            if not recent_files:
                return {
                    'found': False,
                    'error': f"No PNG files created during task execution (after {task_start_time})"
                }
            
            # Sort by timestamp (most recent first) and get the newest
            recent_files.sort(reverse=True)
            creation_time, container_path = recent_files[0]
            filename = os.path.basename(container_path)
            
            logger.info(f"Found screenshot candidate: {filename} (created at {creation_time})")
            
            # Copy the file to host
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_screenshot.close()
            
            copy_from_env(container_path, temp_screenshot.name)
            
            # Verify file has content
            file_size = os.path.getsize(temp_screenshot.name)
            if file_size < 1024:  # Less than 1KB
                os.unlink(temp_screenshot.name)
                return {
                    'found': False,
                    'error': f"Screenshot file is too small ({file_size} bytes)"
                }
            
            return {
                'found': True,
                'local_path': temp_screenshot.name,
                'filename': filename,
                'creation_time': creation_time,
                'error': None
            }
            
        except Exception as e:
            logger.warning(f"Could not use manifest, trying direct file search: {e}")
            # Fallback: try common screenshot filenames
            return find_screenshot_fallback(copy_from_env)
            
    except Exception as e:
        logger.error(f"Error finding screenshot: {e}")
        return {
            'found': False,
            'error': f"Error searching for screenshot: {str(e)}"
        }


def find_screenshot_fallback(copy_from_env) -> Dict:
    """
    Fallback method to find screenshot by trying common filenames.
    """
    # Common screenshot filename patterns
    from datetime import datetime
    today = datetime.now().strftime("%Y-%m-%d")
    
    candidate_names = [
        "screenshot*.png",
        f"screenshot-{today}*.png",
    ]
    
    # Try to find any PNG in Downloads
    downloads_patterns = [
        "/home/ga/Downloads/screenshot.png",
        "/home/ga/Downloads/full-page-screenshot.png",
    ]
    
    # Try each pattern
    for pattern in downloads_patterns:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            temp_file.close()
            
            copy_from_env(pattern, temp_file.name)
            
            if os.path.getsize(temp_file.name) > 1024:
                return {
                    'found': True,
                    'local_path': temp_file.name,
                    'filename': os.path.basename(pattern),
                    'creation_time': time.time(),
                    'error': None
                }
            else:
                os.unlink(temp_file.name)
        except:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
            continue
    
    return {
        'found': False,
        'error': "Could not find screenshot using fallback methods"
    }


def verify_screenshot_quality(
    local_path: str,
    filename: str,
    creation_time: float,
    task_start_time: float
) -> Dict:
    """
    Verify screenshot meets all quality criteria.
    
    Criteria:
    1. File exists and is accessible (already verified)
    2. Created during task timeframe
    3. Valid PNG with full-page dimensions (height > 1000px)
    4. Reasonable file size and valid content
    
    Args:
        local_path: Path to local copy of screenshot
        filename: Original filename
        creation_time: Unix timestamp of file creation
        task_start_time: Unix timestamp when task started
        
    Returns:
        Verification result dict
    """
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Criterion 1: File exists (already verified by getting here)
    feedback_parts.append(f"✓ Screenshot file found: {filename}")
    criteria_met += 1
    
    # Criterion 2: Created during task execution
    time_since_task_start = creation_time - task_start_time
    if time_since_task_start >= -120:  # Allow 2 minutes before task start
        feedback_parts.append(f"✓ File created during task execution ({int(time_since_task_start)}s after task start)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ File appears to be from before task started ({int(time_since_task_start)}s)")
    
    # Criterion 3: Valid PNG with full-page dimensions
    if HAS_PIL:
        try:
            img = Image.open(local_path)
            width, height = img.size
            
            logger.info(f"Screenshot dimensions: {width}x{height}px")
            
            # Check for full-page capture (height should be substantial)
            if height > 1000:
                feedback_parts.append(f"✓ Full-page dimensions detected: {width}x{height}px")
                criteria_met += 1
            else:
                feedback_parts.append(f"✗ Screenshot appears to be viewport-only: {width}x{height}px (height should be >1000px)")
            
            # Additional check: reasonable width
            if not (800 <= width <= 2000):
                feedback_parts.append(f"⚠ Warning: Unusual width {width}px")
            
        except Exception as e:
            feedback_parts.append(f"✗ Invalid PNG or could not read image: {e}")
    else:
        # Fallback without PIL: check file extension and size
        if filename.lower().endswith('.png'):
            feedback_parts.append(f"⚠ PNG format (PIL not available for dimension check)")
            criteria_met += 0.5  # Partial credit
        else:
            feedback_parts.append(f"✗ File is not PNG format")
    
    # Criterion 4: Reasonable file size and content
    file_size_bytes = os.path.getsize(local_path)
    file_size_kb = file_size_bytes / 1024
    
    if 50 <= file_size_kb <= 10240:  # 50KB to 10MB
        feedback_parts.append(f"✓ File size is reasonable: {file_size_kb:.1f} KB")
        
        # Additional content variance check with PIL
        if HAS_PIL:
            try:
                img = Image.open(local_path)
                img_array = np.array(img)
                variance = np.var(img_array)
                
                if variance > 100:  # Has actual content variation
                    criteria_met += 1
                    feedback_parts.append(f"✓ Image contains valid content (variance: {variance:.0f})")
                else:
                    feedback_parts.append(f"✗ Image appears to be blank or solid color (variance: {variance:.0f})")
            except Exception as e:
                logger.warning(f"Could not check content variance: {e}")
                criteria_met += 0.5  # Partial credit if size is good
        else:
            criteria_met += 0.5  # Partial credit without PIL
            
    elif file_size_kb < 50:
        feedback_parts.append(f"✗ File too small: {file_size_kb:.1f} KB (likely incomplete)")
    else:
        feedback_parts.append(f"⚠ File very large: {file_size_kb:.1f} KB (may indicate issue)")
        criteria_met += 0.5  # Partial credit
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PIL:
        feedback += "\n\n⚠ Note: PIL/Pillow not available, some checks had limited functionality"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "filename": filename,
            "file_size_kb": file_size_kb,
            "criteria_met": criteria_met,
            "dimensions": f"{width}x{height}" if HAS_PIL and 'width' in locals() else "unknown"
        }
    }
