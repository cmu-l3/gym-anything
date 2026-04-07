#!/usr/bin/env python3
"""
Verifier for dom_manipulation_threat_report task.

Uses a robust multi-signal verification approach:
1. File Verification: Ensure the screenshot exists and was created during the task.
2. Database Verification: Check places.sqlite to ensure the target URL was actually visited.
3. Programmatic Visual Verification: Pixel density check for the targeted DOM alterations.
4. VLM Verification: Use trajectory frames to check contextual accuracy (URL bar and text).
"""

import os
import json
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dom_manipulation(traj, env_info, task_info):
    """
    Scoring Breakdown (100 points total):
    - File Exists & Valid (Created during task) - 20 pts
    - Valid Network Visit to check.torproject.org - 20 pts
    - Programmatic Color Match (High black background, red text) - 20 pts
    - VLM Context Verification (Right text & URL) - 40 pts
    
    Pass threshold: 80+ points, meaning they must pass VLM and at least most program checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to read task results from environment."}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    logger.info(f"Task result data: {json.dumps(result, indent=2)}")

    # Criterion 1: File Existence (20 pts)
    file_exists = result.get('file_exists', False)
    file_created_during = result.get('file_created_during_task', False)
    image_valid = result.get('image_valid', False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: threat_exhibit.png was not created."
        }
        
    if file_exists and file_created_during and image_valid:
        score += 20
        feedback_parts.append("File exists and is valid (20/20)")
    elif file_exists:
        score += 10
        feedback_parts.append("File exists but may be old or invalid image (10/20)")

    # Criterion 2: Database Network Visit Check (20 pts)
    visited_target = result.get('visited_target_url', False)
    if visited_target:
        score += 20
        feedback_parts.append("Confirmed visit to target URL in history (20/20)")
    else:
        feedback_parts.append("Target URL check.torproject.org not found in browsing history (0/20)")

    # Criterion 3: Programmatic Color Check (20 pts)
    # We expect a high ratio of black background and a tiny but >0 ratio of red pixels for the header
    black_ratio = result.get('black_pixel_ratio', 0.0)
    red_ratio = result.get('red_pixel_ratio', 0.0)
    
    color_matched = False
    if black_ratio > 0.20 and red_ratio > 0.001:
        color_matched = True
        score += 20
        feedback_parts.append(f"Image color analysis matched DOM changes (Black: {black_ratio:.2f}, Red: {red_ratio:.4f}) (20/20)")
    else:
        feedback_parts.append(f"Image color analysis failed. Missing black background or red text. (Black: {black_ratio:.2f}, Red: {red_ratio:.4f}) (0/20)")

    # Criterion 4: VLM Verification using Trajectory Frames (40 pts)
    logger.info("Running VLM verification on trajectory frames...")
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images_to_evaluate = frames + [final]
    
    prompt = """Analyze these trajectory frames of a user operating Tor Browser.
The user's goal was to simulate a defacement on the live DOM of the Tor check page.
Please carefully examine the frames and determine:
1. Is the browser displaying 'check.torproject.org' in the URL address bar?
2. Has the page's background been modified to be completely black?
3. Is there a prominently displayed heading text that has been modified to read exactly "SYSTEM COMPROMISED" in a red color?

If you can verify ALL three conditions are clearly met in the later frames, reply exactly with: "VERIFIED: YES".
If any conditions are not met, reply exactly with: "VERIFIED: NO".
Provide a brief reason on a new line."""

    vlm_result = query_vlm(images=images_to_evaluate, prompt=prompt)
    logger.info(f"VLM Response:\n{vlm_result}")
    
    vlm_passed = False
    if "VERIFIED: YES" in vlm_result.upper():
        vlm_passed = True
        score += 40
        feedback_parts.append("VLM confirmed DOM defacement modifications (40/40)")
    else:
        feedback_parts.append("VLM rejected DOM defacement modifications (0/40)")

    # Final logic
    passed = score >= 80 and file_exists and visited_target

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_valid": image_valid,
            "visited_target": visited_target,
            "color_matched": color_matched,
            "vlm_passed": vlm_passed,
            "vlm_response": vlm_result
        }
    }