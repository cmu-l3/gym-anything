#!/usr/bin/env python3
"""Verifier for animation_mp4_export task.

A post-production coordinator must export dwanko_run.tnz as a video file
(MP4, MOV, AVI, or other standard format) to /home/ga/OpenToonz/output/video_export/.

Scoring (100 points total):
  - Video file exists:          30 pts
  - File size >= 50 KB:         30 pts
  - Created after task start:   25 pts
  - Valid video (ffprobe):      15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

ACCEPTED_EXTENSIONS = {'mp4', 'mov', 'avi', 'webm', 'mkv', 'flv'}


def verify_animation_mp4_export(traj, env_info, task_info):
    """Verify video file export of walk cycle animation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_file_size_kb = metadata.get('min_file_size_kb', 50)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/mp4_export_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Video file exists (30 pts)
    video_found = result.get('video_found', False)
    video_ext = result.get('video_extension', '').lower()
    if video_found:
        if video_ext in ACCEPTED_EXTENSIONS:
            score += 30
            feedback_parts.append(f"Video file found: .{video_ext}")
        else:
            score += 15  # Found something, but unusual format
            feedback_parts.append(f"File found but unusual format: .{video_ext}")
    else:
        feedback_parts.append("No video file found in video_export/ directory")

    # Criterion 2: File size >= 50 KB (30 pts)
    video_size_kb = result.get('video_size_kb', 0)
    if video_size_kb >= min_file_size_kb:
        score += 30
        feedback_parts.append(f"File size OK: {video_size_kb} KB")
    elif video_size_kb >= min_file_size_kb // 4:
        score += 10
        feedback_parts.append(f"File too small: {video_size_kb} KB (expected >= {min_file_size_kb} KB)")
    elif video_size_kb > 0:
        score += 5
        feedback_parts.append(f"File very small: {video_size_kb} KB")
    else:
        feedback_parts.append("Zero-size output file")

    # Criterion 3: Created after task start (25 pts)
    newer_than_start = result.get('video_newer_than_start', False)
    if newer_than_start:
        score += 25
        feedback_parts.append("Video created during this task session")
    elif video_found:
        feedback_parts.append("Video file is pre-existing (not rendered during task)")
    else:
        feedback_parts.append("No new video file")

    # Criterion 4: Valid video file detectable by ffprobe (15 pts)
    ffprobe_valid = result.get('ffprobe_valid', False)
    duration_sec = result.get('video_duration_sec', 0)
    if ffprobe_valid:
        score += 15
        feedback_parts.append(f"Valid video: duration {duration_sec}s (ffprobe verified)")
    elif video_found and video_size_kb >= min_file_size_kb:
        # Give partial credit if file exists and is large enough but ffprobe failed
        score += 5
        feedback_parts.append("Video exists but ffprobe validation failed")
    else:
        feedback_parts.append("Video not valid or not present")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met"
    }
