#!/usr/bin/env python3
"""
Verifier for download_picture_rendition task.

Verifies that:
1. The file 'event_medium.jpg' exists in Downloads.
2. It is a valid JPEG image.
3. Its dimensions match the 'Medium' rendition profile (approx 500-1500px wide).
4. It is NOT the original high-res image (>2500px) or thumbnail (<300px).
5. It was created during the task window.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_download_picture_rendition(traj, env_info, task_info):
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata constraints
    metadata = task_info.get('metadata', {})
    min_width = metadata.get('min_width', 400)
    max_width = metadata.get('max_width', 1600)
    original_threshold = metadata.get('original_min_width', 2500)
    thumbnail_threshold = metadata.get('thumbnail_max_width', 300)

    # Read result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence (20 pts)
    if result.get('file_exists'):
        score += 20
        feedback_parts.append("File found")
    else:
        return {"passed": False, "score": 0, "feedback": "File 'event_medium.jpg' not found in ~/Downloads"}

    # Criterion 2: Valid Image Format (20 pts)
    fmt = result.get('image_format', 'UNKNOWN').upper()
    if 'JPEG' in fmt or 'JPG' in fmt:
        score += 20
        feedback_parts.append("Valid JPEG format")
    elif fmt != 'NONE':
        # Partial credit for correct download but wrong format (e.g., PNG)
        score += 10
        feedback_parts.append(f"Incorrect format: {fmt} (expected JPEG)")
    else:
        feedback_parts.append("Invalid or corrupted file")

    # Criterion 3: Creation Time (Anti-gaming) (Pass/Fail check)
    if not result.get('created_during_task'):
        feedback_parts.append("WARNING: File timestamp predates task start")
        # We penalize heavily if the file looks old, though in a fresh env this is rare
        score = max(0, score - 20)

    # Criterion 4: Dimensions Check (60 pts total)
    width = int(result.get('image_width', 0))
    
    if width == 0:
        feedback_parts.append("Image has 0 width (empty file?)")
    else:
        # Check against "Medium" range
        if min_width <= width <= max_width:
            score += 40
            feedback_parts.append(f"Correct 'Medium' dimensions ({width}px)")
        else:
            feedback_parts.append(f"Incorrect dimensions ({width}px)")

        # Check against Original (High Res)
        if width >= original_threshold:
            feedback_parts.append("Failed: Downloaded Original/Full-Res image")
            score += 0 # No points for original
        else:
            score += 10 # Points for NOT being original

        # Check against Thumbnail
        if width <= thumbnail_threshold:
            feedback_parts.append("Failed: Downloaded Thumbnail")
            score += 0 # No points for thumbnail
        else:
            score += 10 # Points for NOT being thumbnail

    # 3. Final Assessment
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }