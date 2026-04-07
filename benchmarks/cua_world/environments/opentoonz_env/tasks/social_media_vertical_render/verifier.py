#!/usr/bin/env python3
"""
Verifier for social_media_vertical_render task.

Goal: Render animation at 1080x1920 (Portrait/Vertical) @ 30 FPS.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_social_media_vertical_render(traj, env_info, task_info):
    """
    Verify the agent rendered the scene with correct vertical dimensions and frame count.
    """
    # 1. Setup access to results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 1080)
    expected_height = metadata.get('expected_height', 1920)
    min_frames = metadata.get('min_frame_count', 30)
    min_size_kb = metadata.get('min_total_size_kb', 200)

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Criteria
    score = 0
    feedback = []

    # Criterion 1: Frame Count (20 pts)
    frame_count = result.get('frame_count', 0)
    if frame_count >= min_frames:
        score += 20
        feedback.append(f"Frame count sufficient ({frame_count} frames)")
    elif frame_count > 0:
        score += 10
        feedback.append(f"Frame count low ({frame_count}/{min_frames})")
    else:
        feedback.append("No frames rendered")

    # Criterion 2: Width (20 pts)
    actual_width = result.get('img_width', 0)
    if actual_width == expected_width:
        score += 20
        feedback.append(f"Width correct ({actual_width}px)")
    else:
        feedback.append(f"Width incorrect (Expected {expected_width}, Got {actual_width})")

    # Criterion 3: Height (25 pts) - Critical for vertical aspect
    actual_height = result.get('img_height', 0)
    if actual_height == expected_height:
        score += 25
        feedback.append(f"Height correct ({actual_height}px)")
    elif actual_height == 1080 and actual_width == 1920:
         feedback.append("Orientation incorrect (Landscape instead of Portrait)")
    else:
        feedback.append(f"Height incorrect (Expected {expected_height}, Got {actual_height})")

    # Criterion 4: Anti-gaming Timestamp (20 pts)
    files_newer = result.get('files_newer_than_start', 0)
    if files_newer >= min_frames:
        score += 20
        feedback.append("Files created during task session")
    elif files_newer > 0:
        score += 10
        feedback.append("Some files created during task session")
    else:
        feedback.append("No new files created (timestamps pre-date task)")

    # Criterion 5: File Size / Content (15 pts)
    total_size = result.get('total_size_kb', 0)
    if total_size >= min_size_kb:
        score += 15
        feedback.append(f"Output size valid ({total_size} KB)")
    elif total_size > 0:
        score += 5
        feedback.append("Output files appear empty or too small")
    
    # 4. Final Determination
    # Must get orientation right (width & height) AND produce frames to pass
    passed = (score >= 65) and (actual_width == expected_width) and (actual_height == expected_height)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }