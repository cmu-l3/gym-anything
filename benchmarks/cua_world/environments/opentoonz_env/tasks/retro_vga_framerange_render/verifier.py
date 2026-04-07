#!/usr/bin/env python3
"""
Verifier for retro_vga_framerange_render task.

Goal: Render frames 1-12 at 640x480 resolution.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_retro_vga_framerange_render(traj, env_info, task_info):
    """
    Verify the OpenToonz render output.
    
    Scoring Criteria:
    1. Frame Count (30pts): Must be between 10 and 14 files (targeting 12).
    2. Resolution (30pts): Must be exactly 640x480.
    3. New Files (20pts): Files must be created during the task.
    4. Content Size (10pts): Total size > 100KB.
    5. Constraint Bonus (10pts): NOT a full render (count <= 14).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 640)
    expected_height = metadata.get('expected_height', 480)
    min_count = metadata.get('expected_frame_count_min', 10)
    max_count = metadata.get('expected_frame_count_max', 14)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/retro_vga_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metrics
    file_count = result.get('file_count', 0)
    new_file_count = result.get('new_file_count', 0)
    width = result.get('img_width', 0)
    height = result.get('img_height', 0)
    size_kb = result.get('total_size_kb', 0)

    score = 0
    feedback = []

    # 3. Scoring Logic

    # Criterion 1: Frame Count Precision (30 pts)
    # We want exactly 12, but allow slight variance (10-14)
    # If they render 24 (default full scene), they get 0 here.
    if min_count <= file_count <= max_count:
        score += 30
        feedback.append(f"Frame count perfect ({file_count} frames)")
    elif file_count > max_count:
        feedback.append(f"Too many frames rendered ({file_count}). Only frames 1-12 were requested.")
    elif file_count > 0:
        feedback.append(f"Too few frames rendered ({file_count}). Expected 10-14.")
    else:
        feedback.append("No frames rendered.")

    # Criterion 2: Resolution (30 pts)
    if width == expected_width and height == expected_height:
        score += 30
        feedback.append(f"Resolution correct ({width}x{height})")
    elif width > 0:
        feedback.append(f"Wrong resolution: {width}x{height}. Expected {expected_width}x{expected_height}")
    else:
        feedback.append("Could not determine resolution (no images found)")

    # Criterion 3: Freshness (20 pts)
    # At least 80% of the found files must be new
    if file_count > 0 and new_file_count >= (file_count * 0.8):
        score += 20
        feedback.append("Files rendered during task")
    elif file_count > 0:
        feedback.append("Files appear to be pre-existing (timestamps too old)")

    # Criterion 4: Content Size (10 pts)
    if size_kb >= 100:
        score += 10
        feedback.append(f"File size reasonable ({size_kb}KB)")
    else:
        feedback.append(f"File size too small ({size_kb}KB)")

    # Criterion 5: Constraint Bonus (10 pts)
    # Reward for NOT dumping the whole scene, even if other criteria failed slightly
    if 1 <= file_count <= 15:
        score += 10
        feedback.append("Constraint check passed (limited frame range)")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }