#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_paper_texture_multiply_composite(traj, env_info, task_info):
    """
    Verify the Paper Texture Multiply Composite task.
    
    Criteria:
    1. Output frames exist (at least 10)
    2. Frames created during task (anti-gaming)
    3. 'Multiply' effect detected (image darkened)
    4. Texture detected (high frequency noise)
    5. Full coverage (corners are textured)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback = []

    # 1. Check Frame Count (20 pts)
    count = result.get("output_count", 0)
    if count >= 10:
        score += 20
        feedback.append(f"Rendered enough frames ({count})")
    elif count > 0:
        score += 10
        feedback.append(f"Rendered partial frames ({count}/10)")
    else:
        feedback.append("No frames rendered")

    # 2. Check Creation Time (10 pts)
    new_frames = result.get("frames_created_during_task", 0)
    if new_frames >= 10:
        score += 10
        feedback.append("Frames created during task")
    else:
        feedback.append("Frames might be old or pre-existing")

    # 3. Check Multiply Effect (Brightess) (25 pts)
    # The verifier script sets 'is_multiplied' if avg brightness < 250
    # Original 'dwanko_run' is mostly white background (255). 
    # Adding a texture (e.g. 240) via multiply results in 240. 
    # Normal overlay or 'behind' might leave white gaps or be different.
    if result.get("is_multiplied", False):
        score += 25
        feedback.append("Multiply effect detected (Image darkened)")
    else:
        feedback.append("Image too bright - Multiply mode likely missing")

    # 4. Check Texture Presence (Variance) (25 pts)
    # Std dev > 2.0 indicates noise/grain
    if result.get("has_texture", False):
        score += 25
        feedback.append("Paper texture grain detected")
    else:
        feedback.append("Image looks flat - Texture missing or invisible")

    # 5. Check Coverage (Corners) (20 pts)
    # If corners are < 252 brightness, it means texture covers them
    if result.get("full_coverage", False):
        score += 20
        feedback.append("Texture covers full frame")
    else:
        feedback.append("Texture does not cover entire frame (white corners detected)")

    # Pass Threshold
    # Must have rendered AND applied texture (Variance) AND Multiplied (Brightness)
    passed = (score >= 70 and 
              result.get("has_texture") and 
              result.get("is_multiplied"))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }