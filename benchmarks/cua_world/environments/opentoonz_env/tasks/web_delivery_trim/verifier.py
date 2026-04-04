#!/usr/bin/env python3
"""Verifier for web_delivery_trim task.

An animation supervisor must render only frames 1-16 of dwanko_run.tnz at
1280x720 (720p) to /home/ga/OpenToonz/output/web_trim/.

Scoring (100 points total):
  - Frame count 14-20 (correct range): 30 pts
    - Frame count > 20 (full scene rendered): 0 pts for this criterion
    - Frame count < 14: partial credit
  - Resolution 1280x720:               30 pts
  - Files newer than start:            25 pts
  - Total output size >= 100 KB:       15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_web_delivery_trim(traj, env_info, task_info):
    """Verify web delivery frame range trim at 720p."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frame_count', 14)
    max_frames = metadata.get('max_frame_count', 20)
    target_frames = metadata.get('target_frame_count', 16)
    expected_width = metadata.get('expected_width', 1280)
    expected_height = metadata.get('expected_height', 720)
    min_total_size_kb = metadata.get('min_total_size_kb', 100)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/web_trim_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # GATE: Rendering the full scene instead of trimming to frames 1-16 is a
    # fundamental task failure. If > 30 frames exist, the agent did not trim.
    png_count = result.get('png_count', 0)
    if png_count > 30:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"GATE FAIL: {png_count} frames rendered — task requires only frames 1-16. "
                "Full-scene render does not satisfy the web delivery trim requirement."
            )
        }

    # Criterion 1: Frame count — must be in correct range 14-20 (30 pts)
    if min_frames <= png_count <= max_frames:
        score += 30
        feedback_parts.append(f"Frame count correct: {png_count} frames (target 14-20)")
    elif 0 < png_count <= 30:
        partial = int(30 * png_count / min_frames)
        score += partial
        feedback_parts.append(f"Partial frames: {png_count} (expected {min_frames}-{max_frames}, partial: {partial}pts)")
    else:
        feedback_parts.append("No output frames found in web_trim/")

    # Criterion 2: Resolution 1280x720 (30 pts)
    img_width = result.get('img_width', 0)
    img_height = result.get('img_height', 0)
    if img_width == expected_width and img_height == expected_height:
        score += 30
        feedback_parts.append(f"720p resolution correct: {img_width}x{img_height}")
    elif img_width > 0 and img_height > 0:
        feedback_parts.append(
            f"Wrong resolution: {img_width}x{img_height} "
            f"(required 720p {expected_width}x{expected_height})"
        )
    else:
        feedback_parts.append("Could not determine output resolution")

    # Criterion 3: Files created after task start (25 pts)
    files_after_start = result.get('files_after_start', 0)
    if files_after_start >= min_frames:
        score += 25
        feedback_parts.append(f"New render verified: {files_after_start} files after task start")
    elif files_after_start > 0:
        partial = int(25 * min(files_after_start, min_frames) / min_frames)
        score += partial
        feedback_parts.append(f"Some new files: {files_after_start} after start ({partial}pts)")
    else:
        feedback_parts.append("No files created after task start")

    # Criterion 4: Total output size >= 100 KB (15 pts)
    total_size_kb = result.get('total_size_kb', 0)
    if total_size_kb >= min_total_size_kb:
        score += 15
        feedback_parts.append(f"Output size OK: {total_size_kb} KB")
    elif total_size_kb >= min_total_size_kb // 2:
        score += 7
        feedback_parts.append(f"Output marginal: {total_size_kb} KB")
    else:
        feedback_parts.append(f"Output too small: {total_size_kb} KB")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met"
    }
