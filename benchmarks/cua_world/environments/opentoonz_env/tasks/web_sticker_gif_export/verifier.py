#!/usr/bin/env python3
"""
Verifier for web_sticker_gif_export task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_web_sticker_gif_export(traj, env_info, task_info):
    """
    Verify the OpenToonz GIF export task.
    
    Criteria:
    1. Output file exists and is valid GIF (15 pts)
    2. Dimensions are exactly 320x320 (30 pts)
    3. Background is transparent (25 pts)
    4. Animation has multiple frames (15 pts)
    5. File was created during the task (15 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    exp_w = metadata.get('expected_width', 320)
    exp_h = metadata.get('expected_height', 320)

    # 2. Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Check File Existence & Format
    if result.get('file_exists') and result.get('file_size', 0) > 0:
        if result.get('format') == 'GIF':
            score += 15
            feedback.append("Valid GIF file found.")
        else:
            score += 5
            feedback.append(f"File found but format is {result.get('format')} (expected GIF).")
    else:
        feedback.append("No output file found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Check Dimensions
    width = result.get('width', 0)
    height = result.get('height', 0)
    if width == exp_w and height == exp_h:
        score += 30
        feedback.append("Dimensions correct (320x320).")
    else:
        feedback.append(f"Incorrect dimensions: {width}x{height} (expected {exp_w}x{exp_h}).")

    # Check Transparency
    if result.get('is_transparent'):
        score += 25
        feedback.append("Transparency detected.")
    else:
        feedback.append("Background is not transparent (solid color detected).")

    # Check Animation
    frames = result.get('frame_count', 0)
    if frames > 1:
        score += 15
        feedback.append(f"Animation verified ({frames} frames).")
    else:
        feedback.append("Image is static (single frame).")

    # Check Freshness
    if result.get('is_new'):
        score += 15
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")

    # 4. Final Verdict
    # Must have dimensions, transparency, and be a GIF to pass
    passed = (score >= 70) and result.get('is_transparent') and (width == exp_w)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }