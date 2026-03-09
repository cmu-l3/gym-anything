#!/usr/bin/env python3
"""
Verifier for vfx_camera_matchmove_solve task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_matchmove(traj, env_info, task_info):
    """
    Verify the camera tracking result.
    
    Criteria:
    1. Output file exists and modified (10 pts)
    2. Movie clip loaded (10 pts)
    3. Sufficient tracks (>15) (25 pts)
    4. Solve is valid and low error (<1.0 px) (25 pts)
    5. Camera has solver constraint applied (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # 1. File Check
    if result.get("output_exists") and result.get("file_created_during_task"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not saved or not modified.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    analysis = result.get("analysis", {})
    
    # 2. Clip Loaded
    if analysis.get("movie_clip_loaded"):
        score += 10
        feedback.append("Movie clip loaded.")
    else:
        feedback.append("No movie clip found in the blend file.")
    
    # 3. Track Count
    track_count = analysis.get("track_count", 0)
    min_tracks = task_info['metadata'].get('min_track_count', 15)
    if track_count >= min_tracks:
        score += 25
        feedback.append(f"Good track count: {track_count}.")
    elif track_count > 0:
        score += 10
        feedback.append(f"Insufficient tracks: {track_count} (expected > {min_tracks}).")
    else:
        feedback.append("No features tracked.")

    # 4. Solve Quality
    is_solved = analysis.get("is_solved", False)
    solve_error = analysis.get("solve_error", 999.0)
    max_error = task_info['metadata'].get('max_solve_error', 1.0)
    
    if is_solved:
        if solve_error <= max_error:
            score += 25
            feedback.append(f"Excellent solve error: {solve_error:.2f} px.")
        elif solve_error <= 2.0:
            score += 15
            feedback.append(f"Acceptable solve error: {solve_error:.2f} px.")
        else:
            score += 5
            feedback.append(f"High solve error: {solve_error:.2f} px.")
    else:
        feedback.append("Camera motion not solved.")

    # 5. Scene Setup
    if analysis.get("camera_constrained") or analysis.get("camera_animated"):
        score += 30
        feedback.append("Tracking scene set up correctly (camera constrained).")
    else:
        feedback.append("Solved motion not applied to scene camera.")

    passed = score >= task_info['metadata'].get('pass_threshold_score', 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": analysis
    }