#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_animate_column_pan(traj, env_info, task_info):
    """
    Verify that the agent animated the column position to move the character
    from left to right across the frame.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 1280)
    expected_height = metadata.get('expected_height', 720)
    min_frame_count = metadata.get('min_frame_count', 24)
    # Min shift: 15% of width
    min_shift_px = expected_width * metadata.get('min_shift_percent', 0.15)

    # Copy result
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

    score = 0
    feedback_parts = []

    # 1. Check Frame Count (20 pts)
    png_count = result.get('png_count', 0)
    if png_count >= min_frame_count:
        score += 20
        feedback_parts.append(f"Frame count OK ({png_count})")
    elif png_count > 0:
        score += int(20 * (png_count / min_frame_count))
        feedback_parts.append(f"Frame count partial ({png_count}/{min_frame_count})")
    else:
        feedback_parts.append("No frames rendered")

    # 2. Check Resolution (20 pts)
    width = result.get('width', 0)
    height = result.get('height', 0)
    if width == expected_width and height == expected_height:
        score += 20
        feedback_parts.append("Resolution OK")
    elif width > 0:
        feedback_parts.append(f"Wrong resolution ({width}x{height})")

    # 3. Check Freshness (15 pts)
    new_files = result.get('new_files_count', 0)
    if new_files >= min_frame_count:
        score += 15
        feedback_parts.append("Files created during task")
    elif new_files > 0:
        score += 5
        feedback_parts.append("Some files created during task")

    # 4. Check File Size/Content (10 pts)
    if result.get('total_size_kb', 0) > 200:
        score += 10
        feedback_parts.append("Content size reasonable")

    # 5. Check Movement (35 pts) - CRITICAL
    shift_px = result.get('horizontal_shift_px', 0)
    
    # We expect positive shift (Left -> Right)
    if shift_px > min_shift_px:
        score += 35
        feedback_parts.append(f"Character movement detected (Shift: {shift_px:.1f}px)")
    elif shift_px > (min_shift_px * 0.5):
        score += 15
        feedback_parts.append(f"Slight movement detected (Shift: {shift_px:.1f}px)")
    else:
        feedback_parts.append(f"No significant movement detected (Shift: {shift_px:.1f}px)")

    passed = (score >= 60) and (shift_px > min_shift_px)
    
    if not passed and score >= 60:
        feedback_parts.append("FAILED: Movement criterion not met despite high score")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }