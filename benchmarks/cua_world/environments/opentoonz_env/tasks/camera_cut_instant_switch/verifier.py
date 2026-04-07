#!/usr/bin/env python3
"""
Verifier for camera_cut_instant_switch task.

Verifies:
1. 24 frames exist and were created during the task.
2. Frames 1-12 (indices 0-11) are visually stable (Wide Shot).
3. Frames 13-24 (indices 12-23) are visually stable (Close-Up).
4. A significant visual change (Zoom/Cut) occurs exactly between frame 12 and 13.
"""

import json
import os
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_camera_cut_instant_switch(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    # Basic checks
    if not result.get('success', False):
        return {"passed": False, "score": 0, "feedback": f"Analysis script failed: {result.get('error', 'Unknown error')}"}

    frame_count = result.get('frame_count', 0)
    metrics = result.get('frame_metrics', [])
    frames_newer = result.get('frames_newer_than_start', 0)
    
    feedback_parts = []
    score = 0
    
    # Criterion 1: Rendered Frames Count (20 pts)
    if frame_count >= 24:
        score += 20
        feedback_parts.append("Frame count OK (>=24)")
    else:
        feedback_parts.append(f"Insufficient frames: {frame_count}/24")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Freshness (10 pts)
    if frames_newer >= 24:
        score += 10
        feedback_parts.append("Frames are new")
    else:
        feedback_parts.append("Frames are old/pre-existing")
        # Fail immediately if using old files
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Visual Analysis of 'Content Mass'
    # We expect metrics[0:12] to be roughly similar (Wide shot)
    # We expect metrics[12:24] to be roughly similar (Close up)
    # We expect mean(metrics[12:24]) to be significantly larger than mean(metrics[0:12]) (Zoom in = more detail/pixels)
    
    # Normalize metrics to handle potential scale issues, though direct comparison is fine
    # Safe guard against empty metrics
    if len(metrics) < 24:
        return {"passed": False, "score": score, "feedback": "Metrics array incomplete"}

    wide_shot = np.array(metrics[0:12])
    close_up = np.array(metrics[12:24])
    
    wide_mean = np.mean(wide_shot)
    close_mean = np.mean(close_up)
    
    # Calculate Coefficient of Variation (CV) for stability
    # Add small epsilon to avoid div by zero
    wide_cv = np.std(wide_shot) / (wide_mean + 1e-6)
    close_cv = np.std(close_up) / (close_mean + 1e-6)
    
    # Criterion 3: Stability (40 pts)
    # Walk cycle has some natural variance, so we allow some fluctuation
    # But a smooth zoom would cause a high variance trend
    
    stability_pass = True
    if wide_cv < 0.2: # Allow 20% variance for animation movement
        score += 20
        feedback_parts.append("Wide shot stable")
    else:
        stability_pass = False
        feedback_parts.append(f"Wide shot unstable (CV={wide_cv:.2f})")
        
    if close_cv < 0.2:
        score += 20
        feedback_parts.append("Close-up stable")
    else:
        stability_pass = False
        feedback_parts.append(f"Close-up unstable (CV={close_cv:.2f})")

    # Criterion 4: The Cut (30 pts)
    # Check for instant jump
    # 1. Magnitude check
    cut_ratio = close_mean / (wide_mean + 1e-6)
    
    if cut_ratio > 1.3: # At least 30% more pixel mass (conservative estimate for 200% zoom)
        score += 30
        feedback_parts.append(f"Cut verified (Ratio: {cut_ratio:.2f}x)")
    else:
        feedback_parts.append(f"Cut magnitude too small (Ratio: {cut_ratio:.2f}x)")
        
    # Check for smoothness (Anti-Gaming)
    # If it's a smooth zoom, the transition won't be a step function
    # The jump between frame 11 and 12 (0-indexed) should account for most of the difference
    frame_11 = metrics[11]
    frame_12 = metrics[12]
    
    jump_diff = abs(frame_12 - frame_11)
    total_diff = abs(close_mean - wide_mean)
    
    # The single step should cover at least 50% of the total change distance
    if jump_diff > (total_diff * 0.5):
        feedback_parts.append("Transition is instant")
    else:
        # If the jump is small compared to average diff, it might be a smooth zoom
        feedback_parts.append("Warning: Transition appears gradual")
        # Penalize if it looks smooth
        if score >= 10: score -= 10

    passed = (score >= 60) and stability_pass and (cut_ratio > 1.3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }