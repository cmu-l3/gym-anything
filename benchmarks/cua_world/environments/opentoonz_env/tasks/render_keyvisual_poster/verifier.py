#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_render_keyvisual_poster(traj, env_info, task_info):
    """
    Verifies that the agent rendered a single high-res (4K) frame.
    
    Scoring Criteria:
    1. Output PNG exists (15 pts)
    2. Resolution is exactly 3840x2160 (30 pts)
    3. Created during task session (20 pts)
    4. Single frame output (<= 3 files) (15 pts)
    5. Content valid (size > 50kb & non-blank) (20 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 3840)
    expected_height = metadata.get('expected_height', 2160)

    # Read result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read verification data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Data extraction
    file_count = result.get("file_count", 0)
    width = result.get("width", 0)
    height = result.get("height", 0)
    is_newer = result.get("is_newer_than_start", False)
    file_size = result.get("file_size_bytes", 0)
    std_dev = result.get("pixel_std_dev", 0)

    # Criterion 1: File Existence (15 pts)
    if file_count > 0:
        score += 15
        feedback_parts.append("Output file found")
    else:
        feedback_parts.append("No output PNG file found")
        return {"passed": False, "score": 0, "feedback": "No output file found"}

    # Criterion 2: Resolution Check (30 pts)
    # This is the 'Hard' part of the task - changing camera/output settings
    if width == expected_width and height == expected_height:
        score += 30
        feedback_parts.append(f"Resolution correct ({width}x{height})")
    else:
        feedback_parts.append(f"Incorrect resolution: {width}x{height} (Expected: {expected_width}x{expected_height})")

    # Criterion 3: Timestamp Check (20 pts)
    if is_newer:
        score += 20
    else:
        feedback_parts.append("File timestamp is too old (pre-existing file?)")

    # Criterion 4: Single Frame Check (15 pts)
    # Task requested a single frame keyvisual, not a full animation sequence
    # We allow up to 3 files (sometimes people render frame 9, 10, 11 to be safe)
    if 1 <= file_count <= 3:
        score += 15
        feedback_parts.append("Correctly rendered single frame/short range")
    elif file_count > 3:
        feedback_parts.append(f"Rendered too many frames ({file_count}) - expected single poster frame")
    
    # Criterion 5: Content Validity (20 pts)
    # Size > 50KB and Pixel Std Dev > 5 (not a solid color block)
    content_score = 0
    if file_size > 50 * 1024: # 50KB
        content_score += 10
    else:
        feedback_parts.append(f"File size too small ({file_size} bytes)")
        
    if std_dev > 5.0: # Not a solid color
        content_score += 10
    else:
        feedback_parts.append("Image appears to be blank or solid color")
    
    score += content_score

    # 3. Final Result
    passed = score >= 60 and (width == expected_width and height == expected_height)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }