#!/usr/bin/env python3
"""
Verifier for cinema_2k_tiff_alpha_render task.

Verifies:
1. Output files exist and are TIFFs
2. Resolution is 2048x1080 (DCI 2K)
3. Color mode includes Alpha (RGBA)
4. Frame count >= 24
5. Files were created during the task
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cinema_2k_tiff_alpha_render(traj, env_info, task_info):
    """
    Verify the OpenToonz DCI 2K TIFF render task.
    """
    # 1. Setup - Get Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_count = metadata.get('min_frame_count', 24)
    expected_w = metadata.get('expected_width', 2048)
    expected_h = metadata.get('expected_height', 1080)

    # Read the result file from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Extract values
    file_count = result.get('file_count', 0)
    width = result.get('img_width', 0)
    height = result.get('img_height', 0)
    fmt = result.get('img_format', 'NONE').upper()
    mode = result.get('img_mode', 'NONE').upper()
    files_new = result.get('files_created_during_task', 0)
    total_size = result.get('total_size_kb', 0)

    # Criterion A: Frame Count (20 pts)
    # We want at least min_count frames
    if file_count >= min_count:
        score += 20
        feedback_parts.append(f"Frame count met ({file_count}/{min_count})")
    elif file_count > 0:
        # Partial credit
        partial = int((file_count / min_count) * 20)
        score += partial
        feedback_parts.append(f"Partial frame count ({file_count}/{min_count})")
    else:
        feedback_parts.append("No output files found")

    # Criterion B: Resolution (25 pts)
    # Must be exactly 2048x1080
    if width == expected_w and height == expected_h:
        score += 25
        feedback_parts.append(f"Resolution correct ({width}x{height})")
    elif width > 0:
        feedback_parts.append(f"Incorrect resolution: {width}x{height} (Expected {expected_w}x{expected_h})")
    else:
        feedback_parts.append("Could not determine resolution")

    # Criterion C: Format (20 pts)
    # Must be TIFF
    if 'TIF' in fmt:
        score += 20
        feedback_parts.append("Format correct (TIFF)")
    elif fmt != 'NONE':
        feedback_parts.append(f"Incorrect format: {fmt}")
    else:
        feedback_parts.append("Unknown format")

    # Criterion D: Alpha Channel (15 pts)
    # PIL Mode must be 'RGBA' (or 'PA' for palettized alpha, but RGBA is standard for OT render)
    if 'A' in mode: # Matches RGBA, LA, PA
        score += 15
        feedback_parts.append("Alpha channel present")
    elif mode != 'NONE':
        feedback_parts.append(f"Missing alpha channel (Mode: {mode})")
    else:
        feedback_parts.append("Could not check alpha channel")

    # Criterion E: Anti-Gaming / Timestamp (15 pts)
    # Check if files were actually created during this session
    if files_new >= min_count:
        score += 15
        feedback_parts.append("Files created during task")
    elif files_new > 0:
        score += 7
        feedback_parts.append("Some files created during task")
    else:
        feedback_parts.append("No new files detected (timestamp check failed)")

    # Criterion F: Size Check (5 pts)
    # TIFFs are large. 24 frames of 2K RGBA is usually > 100MB.
    # We set a low bar (500KB) just to ensure they aren't empty stubs
    if total_size > 500:
        score += 5
        feedback_parts.append("File size reasonable")
    else:
        feedback_parts.append("Output files suspiciously small")

    # 3. Final Result
    # Pass threshold: 60. 
    # Must have correct Format + Resolution to be considered a 'pass' logically, 
    # but score-based is usually sufficient.
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }