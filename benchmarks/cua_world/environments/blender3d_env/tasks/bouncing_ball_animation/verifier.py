#!/usr/bin/env python3
"""
Verifier for bouncing_ball_animation task.

CRITERIA:
1. Sphere object exists (10 pts)
2. Sphere has Z-location keyframes (15 pts)
3. Animation shows >= 3 ground contacts (bounces) (25 pts)
4. Sphere travels horizontally >= 4 units (15 pts)
5. Z-values vary significantly (showing vertical motion) (10 pts)
6. Frame range is set to 1-120 (10 pts)
7. File is saved and valid (10 pts)
8. Bonus: Realistic energy loss (decreasing peaks) (5 pts)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bouncing_ball(traj, env_info, task_info):
    """
    Verify the bouncing ball animation.
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

    # Extract analysis data
    analysis = result.get('analysis', {})
    if "error" in analysis and analysis["error"] != "File not found or invalid":
        # If valid blend but python script failed
        pass 

    feedback_parts = []
    score = 0
    
    # 1. File saved and valid (10 pts)
    if result.get('output_exists', False) and result.get('is_valid_blend', False):
        if result.get('file_created_during_task', False):
            score += 10
            feedback_parts.append("File saved successfully")
        else:
            score += 5
            feedback_parts.append("File exists but timestamp is old")
    else:
        feedback_parts.append("File NOT saved")
        return {"passed": False, "score": 0, "feedback": "Task failed: No output file found"}

    # 2. Sphere exists (10 pts)
    if analysis.get('sphere_found', False):
        score += 10
        feedback_parts.append(f"Sphere found ('{analysis.get('sphere_name')}')")
    else:
        feedback_parts.append("No sphere object found")

    # 3. Keyframes exist (15 pts)
    kf_count = len(analysis.get('keyframes_z', []))
    if kf_count >= 5:
        score += 15
        feedback_parts.append(f"Z-keyframes present ({kf_count})")
    elif kf_count > 0:
        score += 5
        feedback_parts.append(f"Few Z-keyframes ({kf_count})")
    else:
        feedback_parts.append("No Z-keyframes found")

    # 4. Bounce count (25 pts)
    bounces = analysis.get('bounce_count', 0)
    min_bounces = task_info.get('metadata', {}).get('min_bounces', 3)
    
    if bounces >= min_bounces:
        score += 25
        feedback_parts.append(f"Bounces detected: {bounces}")
    elif bounces > 0:
        score += 10
        feedback_parts.append(f"Only {bounces} bounces detected (need {min_bounces})")
    else:
        feedback_parts.append("No ground contacts detected")

    # 5. Horizontal travel (15 pts)
    travel = analysis.get('horizontal_travel', 0.0)
    min_travel = task_info.get('metadata', {}).get('min_horizontal_travel', 4.0)
    
    if travel >= min_travel:
        score += 15
        feedback_parts.append(f"Horizontal travel good ({travel:.1f} units)")
    elif travel > 0.5:
        score += 5
        feedback_parts.append(f"Minimal horizontal travel ({travel:.1f} units)")
    else:
        feedback_parts.append("Ball is stationary horizontally")

    # 6. Z-variation (10 pts)
    z_var = analysis.get('z_variation', 0.0)
    if z_var > 2.0:
        score += 10
        feedback_parts.append("Vertical motion detected")
    else:
        feedback_parts.append(f"Little vertical motion ({z_var:.1f})")

    # 7. Frame range (10 pts)
    f_start = analysis.get('frame_start', 1)
    f_end = analysis.get('frame_end', 250)
    exp_start = task_info.get('metadata', {}).get('expected_frame_start', 1)
    exp_end = task_info.get('metadata', {}).get('expected_frame_end', 120)
    tol = task_info.get('metadata', {}).get('frame_range_tolerance', 5)
    
    if abs(f_start - exp_start) <= tol and abs(f_end - exp_end) <= tol:
        score += 10
        feedback_parts.append(f"Frame range correct ({f_start}-{f_end})")
    else:
        feedback_parts.append(f"Frame range incorrect ({f_start}-{f_end})")

    # 8. Bonus: Energy decay (5 pts)
    if analysis.get('z_max_decay', False):
        score += 5
        feedback_parts.append("Bonus: Realistic energy loss")

    passed = score >= 60 and analysis.get('sphere_found', False) and bounces > 0

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }