#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hyperstack_reconstruction(traj, env_info, task_info):
    """
    Verifies that the agent reconstructed the hyperstack correctly.
    Requires:
    1. Output file exists and was created during the task.
    2. Channels = 2.
    3. Slices = Total / 2 (Logic: 2 channels * N slices = Total images).
    4. Frames = 1 (Timeframes).
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hyperstack_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    channels = result.get("channels", 0)
    slices = result.get("slices", 0)
    frames = result.get("frames", 0)
    total_images = result.get("total_images", 0)

    # 3. Score Calculation
    score = 0
    feedback = []

    # Criterion 1: File Creation (20 pts)
    if file_exists and created_during:
        score += 20
        feedback.append("Output file created successfully.")
    elif file_exists:
        score += 10
        feedback.append("Output file exists but timestamp suggests it wasn't created during this run.")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Channels (30 pts)
    # The task strictly requires 2 channels (w1 and w2)
    if channels == 2:
        score += 30
        feedback.append("Correct channel count (2).")
    else:
        feedback.append(f"Incorrect channel count: {channels} (Expected 2).")

    # Criterion 3: Slices and Order (30 pts)
    # Total images should be N * 2. So Slices should be Total / 2.
    # We check consistency. If slices == 0, check if total_images matches logical count.
    # Assuming standard BBBC005 subset, if channels=2, then slices must be > 1.
    
    valid_slices = False
    if slices > 1:
        # Check math
        if total_images > 0 and (slices * channels) == total_images:
            valid_slices = True
        # If total_images is not perfectly reported but slices is plausible (e.g. 10-100)
        elif total_images == 0: 
            valid_slices = True
    
    # Also accept if slices * channels * frames == total_images
    expected_total = slices * channels * max(frames, 1)
    
    if valid_slices or (total_images > 0 and expected_total == total_images):
        score += 30
        feedback.append(f"Z-slices configuration appears correct ({slices} slices).")
    else:
        feedback.append(f"Z-slices configuration incorrect or inconsistent (Slices: {slices}, Total: {total_images}).")

    # Criterion 4: Frames (20 pts)
    # Should be 1 timeframe (unless the agent mapped Z to T, which is wrong)
    if frames <= 1:
        score += 20
        feedback.append("Timeframes configuration correct (1).")
    else:
        feedback.append(f"Incorrect timeframes: {frames} (Expected 1). Agent may have confused Z and T.")

    # 4. Final Verification
    passed = score >= 80  # Requires getting channels and slices right
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }