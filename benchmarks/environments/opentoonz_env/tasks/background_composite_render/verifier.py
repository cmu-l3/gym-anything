#!/usr/bin/env python3
"""Verifier for background_composite_render task.

A layout artist must import a background image into dwanko_run.tnz, composite it
behind the character animation, and render 20+ PNG frames at 1920x1080 to
/home/ga/OpenToonz/output/composite_frames/.

Scoring (100 points total):
  - Frame count >= 20:          25 pts
  - Resolution 1920x1080:       30 pts
  - Files newer than start:     25 pts
  - Total output size >= 200KB: 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_background_composite_render(traj, env_info, task_info):
    """Verify background composite render of walk cycle animation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frame_count', 20)
    expected_width = metadata.get('expected_width', 1920)
    expected_height = metadata.get('expected_height', 1080)
    min_total_size_kb = metadata.get('min_total_size_kb', 200)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/composite_render_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Frame count (25 pts)
    png_count = result.get('png_count', 0)
    if png_count >= min_frames:
        score += 25
        feedback_parts.append(f"Frame count OK: {png_count} composite frames")
    elif png_count > 0:
        partial = int(25 * png_count / min_frames)
        score += partial
        feedback_parts.append(f"Partial frames: {png_count}/{min_frames} ({partial}pts)")
    else:
        feedback_parts.append("No composite frames found in composite_frames/")

    # Criterion 2: Resolution 1920x1080 (30 pts)
    img_width = result.get('img_width', 0)
    img_height = result.get('img_height', 0)
    if img_width == expected_width and img_height == expected_height:
        score += 30
        feedback_parts.append(f"Resolution correct: {img_width}x{img_height}")
    elif img_width > 0 and img_height > 0:
        feedback_parts.append(
            f"Wrong resolution: {img_width}x{img_height} "
            f"(expected {expected_width}x{expected_height})"
        )
    else:
        feedback_parts.append("Could not determine output resolution")

    # Criterion 3: New files after task start (25 pts)
    files_after_start = result.get('files_after_start', 0)
    if files_after_start >= min_frames:
        score += 25
        feedback_parts.append(f"Render verified new: {files_after_start} files after task start")
    elif files_after_start > 0:
        partial = int(25 * files_after_start / min_frames)
        score += partial
        feedback_parts.append(f"Some new files: {files_after_start} after start ({partial}pts)")
    else:
        feedback_parts.append("No files created after task start")

    # Criterion 4: Total output size >= 200 KB (20 pts)
    total_size_kb = result.get('total_size_kb', 0)
    if total_size_kb >= min_total_size_kb:
        score += 20
        feedback_parts.append(f"Output size OK: {total_size_kb} KB")
    elif total_size_kb >= min_total_size_kb // 2:
        score += 10
        feedback_parts.append(f"Output marginal: {total_size_kb} KB (expected >= {min_total_size_kb} KB)")
    else:
        feedback_parts.append(f"Output too small: {total_size_kb} KB")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met"
    }
