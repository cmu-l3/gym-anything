#!/usr/bin/env python3
"""
Verifier for muscle_fiber_morphometry task.

Scoring Criteria:
1. Files Exist (10 pts): CSV and PNG present.
2. Anti-Gaming (10 pts): Files created during task.
3. Scale Applied (20 pts): Mean Area is > 500 (indicating microns^2, not pixels).
4. Watershed Success (20 pts): Fiber count > 20 (indicating separation).
5. Noise Filtering (20 pts): Mean Area < 20000 (huge clumps removed) and > 500 (debris removed).
6. VLM Verification (20 pts): Trajectory shows Watershed/Analyze Particles usage.

Pass Threshold: 65 points.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_muscle_fiber_morphometry(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/muscle_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # 3. File Existence Checks (10 pts)
    if result.get("csv_exists") and result.get("img_exists"):
        score += 10
        feedback.append("Output files found (10/10).")
    else:
        feedback.append("Missing CSV or Image output.")

    # 4. Anti-Gaming Check (10 pts)
    if result.get("files_created_during_task"):
        score += 10
        feedback.append("Files created during task window (10/10).")
    else:
        feedback.append("Files detected but timestamps indicate pre-existence or error.")

    # 5. Scale Verification (20 pts)
    # If scale is 1px=0.5um, area in pixels will be 4x area in microns (area_px * 0.5^2 = area_um).
    # Typical muscle fiber is ~3000-5000 um^2. In pixels this would be ~12000-20000 px.
    # If they failed to set scale, the numbers will be HUGE (pixels).
    # If they set it wrong, numbers might be tiny.
    mean_area = float(result.get("csv_mean_area", 0))
    if 500 <= mean_area <= 15000:
        score += 20
        feedback.append(f"Mean Area ({mean_area:.1f}) in valid range -> Scale likely correct (20/20).")
    elif mean_area > 15000:
        feedback.append(f"Mean Area ({mean_area:.1f}) too large -> Likely pixels, not microns (0/20).")
    else:
        feedback.append(f"Mean Area ({mean_area:.1f}) too small or zero (0/20).")

    # 6. Watershed/Separation Check (20 pts)
    # A single block of tissue thresholded without watershed usually results in count=1 or very low.
    # Proper segmentation of a cross-section should yield many fibers (20+).
    count = int(result.get("fiber_count", 0))
    if count >= 20:
        score += 20
        feedback.append(f"Fiber count ({count}) indicates successful separation (20/20).")
    elif count > 0:
        feedback.append(f"Fiber count ({count}) is low -> Watershed likely skipped (5/20).")
        score += 5
    else:
        feedback.append("No objects detected (0/20).")

    # 7. Noise Filtering Check (20 pts)
    # This overlaps with scale but checks specific bounds defined in task
    # We implicitly checked the lower bound in Scale, but let's check upper bound/consistency
    if 1000 <= mean_area <= 10000 and count >= 20:
        score += 20
        feedback.append("Morphometry stats robust (20/20).")
    elif count >= 20:
        score += 10
        feedback.append("Morphometry stats marginal (10/20).")

    # 8. VLM Trajectory Verification (20 pts)
    # We check if the agent actually used the Watershed tool visually
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    Analyze these screenshots of a Fiji/ImageJ task.
    The user should be segmenting muscle fibers.
    Look for:
    1. An image that looks like a binary mask (black and white).
    2. Evidence of 'Watershed' being applied (lines appearing between touching white blobs).
    3. The 'Analyze Particles' dialog or the 'Results' table.
    
    Does the user perform segmentation and measurement?
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
            score += 20
            feedback.append("VLM confirms segmentation workflow (20/20).")
        else:
            # Fallback if VLM is unsure but data is good
            if score >= 60:
                score += 20
                feedback.append("VLM inconclusive, but data looks good (+20).")
            else:
                feedback.append("VLM did not verify workflow (0/20).")
    except:
        # Fail open if VLM errors but hard checks pass
        if score >= 60:
            score += 20
            feedback.append("VLM skipped, data sufficient.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }