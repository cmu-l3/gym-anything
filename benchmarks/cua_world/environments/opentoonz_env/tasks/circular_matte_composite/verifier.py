#!/usr/bin/env python3
"""
Verifier for circular_matte_composite task.

Scoring Criteria:
1. Output Generation (20 pts): Files exist and created during task.
2. Masking (30 pts): Corners are transparent.
3. Visibility (20 pts): Center is visible (not a black screen).
4. Shape (20 pts): The mask aspect ratio suggests a circle (not a full-screen render).
5. Animation (10 pts): The content inside the mask is moving.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_circular_matte_composite(traj, env_info, task_info):
    """
    Verify that the user created a circular matte composite.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frame_count', 24)

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification results: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Frame Count & Creation (20 pts)
    frame_count = result.get("frame_count", 0)
    created_count = result.get("files_created_during_task", 0)
    
    if created_count >= min_frames:
        score += 20
        feedback.append(f"Successfully rendered {created_count} new frames.")
    elif created_count > 0:
        score += 10
        feedback.append(f"Rendered {created_count} frames (expected {min_frames}).")
    else:
        feedback.append("No new frames rendered.")

    # 2. Masking - Corners Transparent (30 pts)
    corners_transparent = result.get("corners_transparent", False)
    if corners_transparent:
        score += 30
        feedback.append("Matte active: Corners are transparent.")
    else:
        feedback.append("Masking failed: Corners are not transparent (image might be full screen).")

    # 3. Center Visibility (20 pts)
    center_visible = result.get("center_visible", False)
    if center_visible:
        score += 20
        feedback.append("Content visible: Center of image contains data.")
    else:
        feedback.append("Visibility failed: Center of image is empty/transparent.")

    # 4. Circular Shape (20 pts)
    is_circular = result.get("is_circular", False)
    if is_circular:
        score += 20
        feedback.append("Shape check: Mask appears circular/symmetric.")
    else:
        # If corners are transparent but shape isn't circular, it might be a weird crop
        if corners_transparent:
            feedback.append("Shape check: Mask is not symmetrical (might not be a circle).")
        else:
            feedback.append("Shape check: N/A (no mask detected).")

    # 5. Animation Motion (10 pts)
    has_motion = result.get("has_motion", False)
    if has_motion:
        score += 10
        feedback.append("Animation check: Motion detected inside the mask.")
    else:
        feedback.append("Animation check: Output appears static (no motion).")

    # Error reporting
    if result.get("error"):
        feedback.append(f"Analysis warning: {result.get('error')}")

    # Pass logic: Must have mask working and content visible
    passed = score >= 70 and corners_transparent and center_visible

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }