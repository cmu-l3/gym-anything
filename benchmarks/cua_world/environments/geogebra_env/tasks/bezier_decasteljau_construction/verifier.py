#!/usr/bin/env python3
"""
Verifier for Bézier Curve de Casteljau Construction task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bezier_decasteljau_construction(traj, env_info, task_info):
    """
    Verify the Bézier curve construction based on exported XML analysis.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File Existence & Creation (15 pts)
    if result.get("file_found") and result.get("file_created_during_task"):
        score += 15
        feedback.append("File created successfully during task (+15)")
    elif result.get("file_found"):
        score += 5
        feedback.append("File found, but timestamp check failed (pre-existing?) (+5)")
    else:
        feedback.append("File not found (0)")

    # 2. Control Points (20 pts)
    # 5 pts per correct point
    found_pts = result.get("control_points_found", 0)
    pts_score = found_pts * 5
    score += pts_score
    if found_pts == 4:
        feedback.append("All 4 control points correct (+20)")
    else:
        feedback.append(f"{found_pts}/4 control points correct (+{pts_score})")

    # 3. Slider (15 pts)
    if result.get("slider_found"):
        score += 15
        feedback.append("Slider parameter found (+15)")
    else:
        feedback.append("No slider found (0)")

    # 4. Control Polygon (Segments) (10 pts)
    # We expect at least 3 segments for the base polygon
    seg_count = result.get("segments_count", 0)
    if seg_count >= 3:
        score += 10
        feedback.append(f"Control polygon segments found ({seg_count}) (+10)")
    elif seg_count > 0:
        score += 5
        feedback.append(f"Some segments found, but fewer than expected for full construction (+5)")
    else:
        feedback.append("No segments found (0)")

    # 5. Intermediate Points (20 pts)
    # Full De Casteljau for cubic requires:
    # Level 1: 3 pts
    # Level 2: 2 pts
    # Level 3: 1 pt (the curve point)
    # Total 6 intermediate points.
    inter_count = result.get("intermediate_points_count", 0)
    if inter_count >= 5:
        score += 20
        feedback.append(f"De Casteljau intermediate points structure found ({inter_count} points) (+20)")
    elif inter_count >= 1:
        score += 10
        feedback.append("Some intermediate points found, but construction seems incomplete (+10)")
    else:
        feedback.append("No intermediate construction points found (0)")

    # 6. Bézier Curve Trace (20 pts)
    if result.get("curve_command_found"):
        score += 20
        feedback.append("Bézier curve command (Curve/Locus) found (+20)")
    else:
        feedback.append("Final Curve or Locus command not found (0)")

    # Pass Threshold
    passed = (score >= 70) and result.get("curve_command_found")
    
    # Gate: Must have the curve to pass, even if other points add up
    if score >= 70 and not result.get("curve_command_found"):
        feedback.append("FAIL: Score sufficient, but final Curve/Locus is missing.")
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }