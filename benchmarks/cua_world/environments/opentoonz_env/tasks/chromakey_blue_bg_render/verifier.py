#!/usr/bin/env python3
"""
Verifier for chromakey_blue_bg_render task.

Verifies:
1. Frame count (>= 24)
2. Background color correctness (Target: RGB 0, 71, 171)
3. File creation timestamps (Anti-gaming)
4. File validity/size
"""

import json
import os
import tempfile
import math

def verify_chromakey_blue_bg_render(traj, env_info, task_info):
    """
    Verify that the animation was rendered with the correct blue background.
    """
    # 1. Setup & Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_rgb = metadata.get('target_rgb', [0, 71, 171])
    tolerance = metadata.get('tolerance', 30)
    min_frame_count = metadata.get('min_frame_count', 24)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get("analysis", {})
    if analysis.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Analysis error: {analysis['error']}"}

    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Frames Exist and Count (20 pts)
    frame_count = analysis.get("frame_count", 0)
    if frame_count >= min_frame_count:
        score += 20
        feedback_parts.append(f"Frame count OK ({frame_count})")
    elif frame_count > 0:
        score += int(20 * (frame_count / min_frame_count))
        feedback_parts.append(f"Partial frame count ({frame_count}/{min_frame_count})")
    else:
        feedback_parts.append("No frames found")

    # Criterion 2: Anti-gaming Timestamp Check (20 pts)
    if analysis.get("files_created_during_task", False) and frame_count > 0:
        score += 20
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Files NOT created during task (or no files)")

    # Criterion 3: Background Color Match (35 pts)
    # This is the core 'hard' part of the task
    detected_bg = analysis.get("avg_bg_color", [0, 0, 0])
    is_transparent = analysis.get("is_transparent", False)
    
    if is_transparent:
        feedback_parts.append("Background is transparent (Fail)")
        # 0 points for color if transparent
    else:
        # Calculate color distance
        dist = math.sqrt(
            (detected_bg[0] - target_rgb[0])**2 +
            (detected_bg[1] - target_rgb[1])**2 +
            (detected_bg[2] - target_rgb[2])**2
        )
        
        if dist <= tolerance:
            score += 35
            feedback_parts.append(f"Background color exact match (Diff: {dist:.1f})")
        elif dist <= tolerance * 2:
            score += 15
            feedback_parts.append(f"Background color close but off (Diff: {dist:.1f})")
        else:
            feedback_parts.append(f"Wrong background color. Detected: {detected_bg}, Target: {target_rgb}")

    # Criterion 4: File Size / Content (15 pts)
    total_size_kb = analysis.get("total_size_kb", 0)
    if total_size_kb >= 200:
        score += 15
        feedback_parts.append(f"Content size OK ({total_size_kb:.0f}KB)")
    elif total_size_kb > 0:
        score += 5
        feedback_parts.append("Content size too small")

    # Criterion 5: Valid Dimensions (10 pts)
    # Implicitly checked if analysis didn't error, giving points for valid image format
    if frame_count > 0 and not analysis.get("error"):
        score += 10
        feedback_parts.append("Valid image format")

    # 3. Final Result
    passed = (score >= 60) and (not is_transparent) and (frame_count >= 1)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }