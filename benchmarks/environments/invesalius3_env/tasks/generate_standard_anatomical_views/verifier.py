#!/usr/bin/env python3
"""
Verifier for generate_standard_anatomical_views task.

Criteria:
1. Files Exist (20 pts): anterior.png, posterior.png, left.png, right.png
2. Valid Format (10 pts): Files are valid PNGs.
3. White Background (30 pts): Corners of the images are white (RGB 255,255,255).
4. Distinct Views (40 pts): The images are not identical copies (simple perceptual hash check).

Pass Threshold: 60 points (must have files and correct background).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_anatomical_views(traj, env_info, task_info):
    """Verify standard anatomical view generation."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # Load results
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read export result: {e}"
        }

    # 1. Check Files Existence (20 pts)
    # 5 pts per file
    files_found = result.get("files_found", [])
    expected = ["anterior.png", "posterior.png", "left.png", "right.png"]
    
    found_count = len(files_found)
    score += found_count * 5
    
    if found_count == 4:
        feedback_parts.append("All 4 view files created")
    else:
        missing = [f for f in expected if f not in files_found]
        feedback_parts.append(f"Missing files: {', '.join(missing)}")

    # 2. Check Valid PNGs (10 pts)
    valid_count = result.get("valid_pngs", 0)
    if valid_count == 4:
        score += 10
        feedback_parts.append("All files are valid PNGs")
    elif valid_count > 0:
        score += int((valid_count / 4) * 10)
        feedback_parts.append(f"Only {valid_count}/4 files are valid PNGs")

    # 3. Check White Background (30 pts)
    # This proves they changed the setting
    bg_count = result.get("white_background_count", 0)
    if bg_count == 4:
        score += 30
        feedback_parts.append("Background is white for all views")
    elif bg_count > 0:
        partial = int((bg_count / 4) * 30)
        score += partial
        feedback_parts.append(f"Background white in only {bg_count}/4 views")
    else:
        feedback_parts.append("Background does not appear to be white (check corners)")

    # 4. Check Distinct Images (40 pts)
    # This proves they actually rotated the model and didn't just save the same view 4 times
    if found_count == 4 and result.get("distinct_images", False):
        score += 40
        feedback_parts.append("All views are visually distinct")
    elif found_count > 1 and not result.get("distinct_images", False):
        feedback_parts.append("FAIL: Some images appear identical (duplicate views)")
    
    # Calculate pass status
    # Must have at least 60 points
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }