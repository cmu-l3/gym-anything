#!/usr/bin/env python3
"""
Verifier for nla_camera_shake_layering task.

Criteria:
1. File exists and was saved during task.
2. Camera object has NLA tracks (at least 2).
3. 'Dolly_Move' action exists as a strip.
4. 'Handheld_Shake' action exists as a strip.
5. Shake strip uses ADD or COMBINE blend mode.
6. Evaluation confirms both Location (Dolly) and Rotation (Shake) changes.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nla_layering(traj, env_info, task_info):
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

    # Basic file checks
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not saved during the task."}

    analysis = result.get("analysis", {})
    if "error" in analysis:
        return {"passed": False, "score": 0, "feedback": f"File analysis failed: {analysis['error']}"}

    score = 0
    feedback = []

    # 1. Check NLA Tracks (30 pts)
    # Should have at least 2 tracks (one pushed down, one new)
    track_count = analysis.get("nla_track_count", 0)
    tracks = analysis.get("tracks", [])
    if track_count >= 2:
        score += 30
        feedback.append(f"Found {track_count} NLA tracks (Good).")
    else:
        feedback.append(f"Found {track_count} NLA tracks (Expected at least 2).")

    # 2. Identify Strips (40 pts)
    has_dolly = False
    has_shake = False
    shake_blend_mode = "REPLACE"
    
    for track in tracks:
        for strip in track.get("strips", []):
            action_name = strip.get("action", "")
            if "Dolly" in action_name:
                has_dolly = True
            if "Shake" in action_name or "Handheld" in action_name:
                has_shake = True
                shake_blend_mode = strip.get("blend_type", "REPLACE")

    if has_dolly:
        score += 20
        feedback.append("Dolly action strip present.")
    else:
        feedback.append("Missing Dolly action strip.")

    if has_shake:
        score += 20
        feedback.append("Shake action strip present.")
    else:
        feedback.append("Missing Shake action strip.")

    # 3. Check Blending Mode (15 pts)
    # Must be ADD or COMBINE to layer properly
    if has_shake:
        if shake_blend_mode in ["ADD", "COMBINE"]:
            score += 15
            feedback.append(f"Shake blend mode correct ({shake_blend_mode}).")
        else:
            feedback.append(f"Shake blend mode incorrect ({shake_blend_mode}). Should be ADD or COMBINE.")

    # 4. Evaluate Animation (15 pts)
    # Check frame 50. 
    # Location Y should be > 2 (Dolly effect)
    # Rotation X/Z should be != 0 (Shake effect, approx)
    eval_data = analysis.get("evaluation", {})
    f50 = eval_data.get("frame_50", {})
    
    loc_y = f50.get("loc", [0, 0, 0])[1]
    rot_x = f50.get("rot", [0, 0, 0])[0]
    
    # Original rotation was 1.5708 (90 deg). Noise adds small deviation.
    # Original Loc Y was moving 0->10. At frame 50 it should be ~5.0.
    
    loc_moved = abs(loc_y) > 1.0
    rot_shook = abs(rot_x - 1.5708) > 0.001 # Check for any deviation from static
    
    if loc_moved and rot_shook:
        score += 15
        feedback.append("Animation evaluates correctly (Moves and Shakes).")
    elif not loc_moved:
        feedback.append(f"Camera not moving in Y (Y={loc_y:.2f}). Dolly track may be muted or missing.")
    elif not rot_shook:
        feedback.append(f"Camera not shaking (RotX={rot_x:.4f}). Shake track may be muted or Blend mode is Replace.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }