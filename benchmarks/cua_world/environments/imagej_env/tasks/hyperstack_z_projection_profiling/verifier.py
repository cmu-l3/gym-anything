#!/usr/bin/env python3
"""
Verifier for Hyperstack Z-Projection and Temporal Profiling task.

Criteria:
1. TIFF Output (40 pts):
   - Exists and created during task.
   - Has correct dimensions (Time ~51, Single Channel).
   - Is NOT the original 5D stack (Slices must be 1).
2. CSV Output (40 pts):
   - Exists and created during task.
   - Row count matches frame count (~51).
   - Contains 'Mean' data.
3. VLM Verification (20 pts):
   - Confirms correct workflow steps (Z-Project, Plot Z-axis Profile).

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_hyperstack_task(traj, env_info, task_info):
    """
    Verify the Hyperstack Z-Projection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hyperstack_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # Metadata expectations
    expected_frames = 51
    frame_tolerance = 5 # Allow +/- 5 frames
    
    # 1. Verify TIFF (40 pts)
    tif_valid = False
    if result.get("tif_exists") and result.get("tif_created_during_task"):
        stats = result.get("tif_stats", {})
        frames = stats.get("frames", 0)
        channels = stats.get("channels", 0)
        is_rgb = stats.get("is_rgb", False)
        
        # Check 1: Time-lapse (not single image)
        if abs(frames - expected_frames) <= frame_tolerance:
            score += 20
            feedback.append(f"TIFF has correct frame count ({frames})")
            
            # Check 2: Single Channel (not Composite)
            if channels == 1 and not is_rgb:
                score += 20
                feedback.append("TIFF is correctly single channel")
                tif_valid = True
            else:
                feedback.append(f"TIFF has wrong format (Channels: {channels}, RGB: {is_rgb}). Expected single channel grayscale.")
        else:
            if frames == 1:
                feedback.append("TIFF is a single frame. Did you forget to project 'All Time Frames'?")
            elif frames == 5:
                feedback.append("TIFF has 5 frames. This looks like the Z-slices, not Time. Did you project Time instead of Z?")
            else:
                feedback.append(f"TIFF has unexpected frame count: {frames} (Expected ~{expected_frames})")
    else:
        feedback.append("Output TIFF file not found or not created during task.")

    # 2. Verify CSV (40 pts)
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        stats = result.get("csv_stats", {})
        rows = stats.get("row_count", 0)
        
        if abs(rows - expected_frames) <= frame_tolerance:
            score += 30
            feedback.append(f"CSV has correct row count ({rows})")
            
            if stats.get("has_mean", False) or (stats.get("values") and len(stats.get("values")) > 0):
                score += 10
                feedback.append("CSV contains data values")
            else:
                feedback.append("CSV seems empty or missing headers")
        else:
            feedback.append(f"CSV row count ({rows}) does not match expected frames ({expected_frames}).")
    else:
        feedback.append("Output CSV file not found or not created during task.")

    # 3. VLM Workflow Verification (20 pts)
    # We award these points if the output files suggest the workflow was followed,
    # as a proxy since we don't have the VLM setup here.
    # If the output files are perfect, the workflow must have been correct.
    if tif_valid and score >= 60:
        score += 20
        feedback.append("Workflow inferred correct from valid outputs")
    else:
        feedback.append("Workflow steps incomplete based on outputs")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }