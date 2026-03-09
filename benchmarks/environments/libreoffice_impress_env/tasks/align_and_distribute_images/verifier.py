#!/usr/bin/env python3
"""
Verifier for Align and Distribute Images task.
"""

import json
import tempfile
import os
import logging
import math
import numpy as np
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_alignment_and_distribution(traj, env_info, task_info):
    """
    Verifies that images are aligned vertically and distributed horizontally.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Modification (10 pts)
    if result.get("file_modified", False):
        score += 10
        feedback_parts.append("✅ File saved")
    else:
        feedback_parts.append("❌ File not saved/modified")

    # 2. Geometric Verification (80 pts total)
    geo = result.get("geometry", {})
    if not geo.get("success", False):
        return {"passed": False, "score": score, "feedback": f"Failed to parse ODP: {geo.get('error')}"}

    frames = geo.get("frames", [])
    
    # Check image count (10 pts)
    if len(frames) == 3:
        score += 10
        feedback_parts.append("✅ 3 images preserved")
    else:
        return {"passed": False, "score": score, "feedback": f"❌ Expected 3 images, found {len(frames)}"}

    # Calculate Centers and Gaps
    # Vertical Centers (y + h/2)
    y_centers = [f["y"] + (f["height"] / 2.0) for f in frames]
    
    # Horizontal Gaps
    # Frames are already sorted by X in export script
    gaps = []
    for i in range(len(frames) - 1):
        # Gap = Next_X - (Current_X + Current_Width)
        gap = frames[i+1]["x"] - (frames[i]["x"] + frames[i]["width"])
        gaps.append(gap)

    # 3. Verify Vertical Alignment (40 pts)
    # Standard deviation of centers should be close to 0
    y_std = np.std(y_centers)
    tolerance = 0.05  # cm
    
    if y_std <= tolerance:
        score += 40
        feedback_parts.append(f"✅ Vertical alignment perfect (std dev: {y_std:.4f})")
    else:
        feedback_parts.append(f"❌ Vertical alignment off (std dev: {y_std:.4f} > {tolerance})")

    # 4. Verify Horizontal Distribution (40 pts)
    # Difference between gaps should be close to 0
    if len(gaps) >= 2:
        gap_diff = abs(gaps[0] - gaps[1])
        if gap_diff <= tolerance:
            score += 40
            feedback_parts.append(f"✅ Horizontal distribution perfect (diff: {gap_diff:.4f})")
        else:
            feedback_parts.append(f"❌ Horizontal distribution off (diff: {gap_diff:.4f} > {tolerance})")
    else:
        feedback_parts.append("❌ Cannot calculate gaps (too few images)")

    # 5. VLM Verification (Bonus/Tie-breaker check)
    # We use this mainly to ensure no "cheating" like deleting everything else
    final_ss = get_final_screenshot(traj)
    if final_ss:
        vlm_res = query_vlm(
            image=final_ss, 
            prompt="Are there 3 product images aligned in a row on this slide? Reply with YES or NO."
        )
        if vlm_res.get("parsed", {}).get("answer", "").lower() == "yes":
            feedback_parts.append("(Visual confirmation pass)")
        
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }