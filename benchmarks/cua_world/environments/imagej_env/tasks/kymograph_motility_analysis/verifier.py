#!/usr/bin/env python3
"""Verifier for Kymograph Motility Analysis task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_kymograph(traj, env_info, task_info):
    """
    Verify Kymograph Generation.
    
    Success Logic:
    1. Kymograph file must exist and be valid.
    2. CRITICAL: Kymograph height must equal the number of time frames in source (51).
       - If user reslices Z (5 slices), height will be 5 -> FAIL.
       - If user reslices Time (51 frames), height will be 51 -> PASS.
    3. Projection file should exist and represent the time series (51 frames).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_height = metadata.get('expected_kymograph_height', 51)
    min_width = metadata.get('min_kymograph_width', 20)
    
    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/kymograph_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. Verify Kymograph Existence (20 pts)
    if result.get("kymo_exists") and result.get("kymo_created_after_start"):
        score += 20
        feedback.append("Kymograph file created.")
    else:
        feedback.append("FAIL: Kymograph file not found or not created during task.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Kymograph Geometry (40 pts) - CRITICAL
    # Height must match time frames (51)
    # Width depends on line length drawn by user, but should be reasonable (>20px)
    actual_height = result.get("kymo_height", 0)
    actual_width = result.get("kymo_width", 0)
    
    if actual_height == expected_height:
        score += 40
        feedback.append(f"Correct temporal dimensions (Height={actual_height}px).")
    elif actual_height == 5:
        feedback.append("FAIL: It looks like you resliced the Z-axis (height=5) instead of Time (height=51).")
    else:
        feedback.append(f"FAIL: Incorrect kymograph height ({actual_height}px). Expected {expected_height}px (one per time frame).")

    # 3. Verify Line Selection (Width) (10 pts)
    if actual_width >= min_width:
        score += 10
        feedback.append(f"Line selection width reasonable ({actual_width}px).")
    else:
        feedback.append(f"FAIL: Result image too narrow ({actual_width}px). Did you draw a line across the cell?")

    # 4. Verify Projection (30 pts)
    # Checks if they correctly did the Z-projection step
    if result.get("proj_exists"):
        score += 15
        feedback.append("Intermediate projection file found.")
        
        proj_frames = result.get("proj_frames", 0)
        if proj_frames == expected_height:
            score += 15
            feedback.append(f"Projection correctly preserves time series ({proj_frames} frames).")
        elif proj_frames == 1:
            feedback.append("FAIL: Projection is a single frame. You likely projected over 'All time frames' or didn't check the box.")
        else:
            feedback.append(f"Projection has unexpected frame count: {proj_frames}.")
    else:
        feedback.append("Intermediate projection file missing.")

    return {
        "passed": score >= 60 and actual_height == expected_height,
        "score": score,
        "feedback": " | ".join(feedback)
    }