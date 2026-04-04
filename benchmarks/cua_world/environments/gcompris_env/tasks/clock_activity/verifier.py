#!/usr/bin/env python3
"""
Verifier for clock_activity task (GCompris).

Verification Strategy:
1. File Existence & Timestamp: Check /tmp/clock_before.png and /tmp/clock_after.png
   were created during the task.
2. Image Difference (Programmatic):
   - 'before' image must differ from 'initial' (proving navigation).
   - 'after' image must differ from 'before' (proving interaction).
3. VLM Verification:
   - Verify trajectory shows navigation to clock activity.
   - Verify interaction with clock hands.
"""

import json
import os
import tempfile
import logging
import math
from PIL import Image, ImageChops
import numpy as np

# Import VLM utils from framework
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_image_difference(img1_path, img2_path):
    """Calculate RMS difference between two images."""
    try:
        if not os.path.exists(img1_path) or not os.path.exists(img2_path):
            return 0.0
        
        im1 = Image.open(img1_path).convert('RGB')
        im2 = Image.open(img2_path).convert('RGB')
        
        # Resize to match smaller dimensions if needed
        if im1.size != im2.size:
            im2 = im2.resize(im1.size)
            
        diff = ImageChops.difference(im1, im2)
        h = diff.histogram()
        sq = (value * ((idx % 256) ** 2) for idx, value in enumerate(h))
        sum_of_squares = sum(sq)
        rms = math.sqrt(sum_of_squares / float(im1.size[0] * im1.size[1]))
        return rms
    except Exception as e:
        logger.error(f"Error comparing images: {e}")
        return 0.0

def verify_clock_activity(traj, env_info, task_info):
    """Verify GCompris clock activity task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Screenshots for analysis
    initial_path = "/tmp/initial_local.png"
    before_path = "/tmp/before_local.png"
    after_path = "/tmp/after_local.png"
    
    # Try copying files
    files_retrieved = {}
    for remote, local in [
        ("/tmp/task_initial.png", initial_path),
        ("/tmp/clock_before.png", before_path),
        ("/tmp/clock_after.png", after_path)
    ]:
        try:
            copy_from_env(remote, local)
            files_retrieved[remote] = True
        except:
            files_retrieved[remote] = False

    # --- SCORING CRITERIA ---

    # Criterion 1: File Existence & Validity (30 pts)
    before_stats = result.get("clock_before", {})
    after_stats = result.get("clock_after", {})
    
    if before_stats.get("exists") and before_stats.get("created_during_task") and before_stats.get("size", 0) > 5000:
        score += 15
        feedback_parts.append("Before screenshot valid.")
    else:
        feedback_parts.append("Before screenshot missing/invalid.")

    if after_stats.get("exists") and after_stats.get("created_during_task") and after_stats.get("size", 0) > 5000:
        score += 15
        feedback_parts.append("After screenshot valid.")
    else:
        feedback_parts.append("After screenshot missing/invalid.")

    # Criterion 2: Navigation Verification (20 pts)
    # 'Before' screenshot must differ significantly from 'Initial'
    nav_diff = 0
    if files_retrieved.get("/tmp/task_initial.png") and files_retrieved.get("/tmp/clock_before.png"):
        nav_diff = calculate_image_difference(initial_path, before_path)
        if nav_diff > 30.0:  # Threshold for significant UI change
            score += 20
            feedback_parts.append("Navigation verified (screen changed).")
        else:
            feedback_parts.append(f"Navigation doubtful (screen similarity high, diff={nav_diff:.1f}).")
    else:
        feedback_parts.append("Cannot verify navigation (missing images).")

    # Criterion 3: Interaction Verification (20 pts)
    # 'After' screenshot must differ from 'Before'
    interact_diff = 0
    if files_retrieved.get("/tmp/clock_before.png") and files_retrieved.get("/tmp/clock_after.png"):
        interact_diff = calculate_image_difference(before_path, after_path)
        if interact_diff > 10.0:  # Threshold for hand movement/success message
            score += 20
            feedback_parts.append("Interaction verified (clock state changed).")
        else:
            feedback_parts.append(f"Interaction doubtful (no visible change, diff={interact_diff:.1f}).")
    else:
        feedback_parts.append("Cannot verify interaction (missing images).")

    # Criterion 4: VLM Verification of Content (30 pts)
    # Check if the agent actually found the CLOCK activity and not something else
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    if final:
        frames.append(final)
    
    vlm_prompt = """
    You are verifying an agent's performance in GCompris education software.
    The task was to open the 'Learn to tell time' activity (Clock game) and set the time.
    
    Look at these screenshots.
    1. Do you see an analog clock face in any of the images?
    2. Does it look like the agent successfully set the time or finished a round?
    
    Respond in JSON:
    {
        "clock_visible": true/false,
        "success_indication": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("clock_visible"):
            score += 20
            feedback_parts.append("VLM confirmed clock activity.")
            if parsed.get("success_indication"):
                score += 10
                feedback_parts.append("VLM confirmed success state.")
        else:
            feedback_parts.append("VLM did not see a clock.")
    else:
        feedback_parts.append("VLM verification failed to run.")

    # Cleanup local files
    for p in [initial_path, before_path, after_path]:
        if os.path.exists(p):
            os.unlink(p)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }