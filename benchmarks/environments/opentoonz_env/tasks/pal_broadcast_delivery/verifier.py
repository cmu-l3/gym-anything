#!/usr/bin/env python3
"""Verifier for pal_broadcast_delivery task.

A technical director must render dwanko_run.tnz at PAL SD resolution (720x576)
and 25fps, outputting at least 25 PNG frames to /home/ga/OpenToonz/output/pal_delivery/.

Scoring (100 points total):
  - Frame count >= 25:          25 pts
  - Resolution 720x576:         35 pts  (primary PAL discriminator)
  - Files newer than start:     25 pts
  - Total output size >= 150KB: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_pal_broadcast_delivery(traj, env_info, task_info):
    """Verify PAL broadcast delivery render."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frame_count', 25)
    expected_width = metadata.get('expected_width', 720)
    expected_height = metadata.get('expected_height', 576)
    min_total_size_kb = metadata.get('min_total_size_kb', 150)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pal_delivery_result.json", temp_file.name)
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
        feedback_parts.append(f"Frame count OK: {png_count} frames")
    elif png_count > 0:
        partial = int(25 * png_count / min_frames)
        score += partial
        feedback_parts.append(f"Partial frames: {png_count}/{min_frames} ({partial}pts)")
    else:
        feedback_parts.append("No output frames found in pal_delivery/")

    # Criterion 2: PAL resolution 720x576 (35 pts — primary discriminator)
    img_width = result.get('img_width', 0)
    img_height = result.get('img_height', 0)
    if img_width == expected_width and img_height == expected_height:
        score += 35
        feedback_parts.append(f"PAL resolution correct: {img_width}x{img_height}")
    elif img_width > 0 and img_height > 0:
        feedback_parts.append(
            f"Wrong resolution: {img_width}x{img_height} "
            f"(required PAL {expected_width}x{expected_height})"
        )
    else:
        feedback_parts.append("Could not determine output resolution")

    # Criterion 3: New files created after task start (25 pts)
    files_after_start = result.get('files_after_start', 0)
    if files_after_start >= min_frames:
        score += 25
        feedback_parts.append(f"New render verified: {files_after_start} files after task start")
    elif files_after_start > 0:
        partial = int(25 * files_after_start / min_frames)
        score += partial
        feedback_parts.append(f"Some new files: {files_after_start} after task start ({partial}pts)")
    else:
        feedback_parts.append("No files created after task start")

    # Criterion 4: Total output size (15 pts)
    total_size_kb = result.get('total_size_kb', 0)
    if total_size_kb >= min_total_size_kb:
        score += 15
        feedback_parts.append(f"Output size OK: {total_size_kb} KB")
    elif total_size_kb >= min_total_size_kb // 2:
        score += 7
        feedback_parts.append(f"Output marginal size: {total_size_kb} KB")
    else:
        feedback_parts.append(f"Output too small: {total_size_kb} KB (expected >= {min_total_size_kb} KB)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met"
    }
