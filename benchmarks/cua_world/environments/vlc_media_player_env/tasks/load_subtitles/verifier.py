#!/usr/bin/env python3
"""
Verifier for Load Subtitles task
"""

import sys
import os
import logging
import tempfile
import json

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_load_subtitles(traj, env_info, task_info):
    """
    Verify load subtitles task completion.

    Checks:
    1. Subtitles result file exists and is valid
    2. Subtitle file path or track is present
    3. Subtitles were enabled
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy subtitles result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/vlc_subtitles_result.json", temp_result.name)

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Subtitles result accessible")

        # Get subtitle info from result
        subtitle_file = result.get('subtitle_file', '')
        subtitle_track = result.get('subtitle_track', '')
        subtitle_enabled = result.get('subtitle_enabled', False)
        config_found = result.get('config_found', False)

        # Check if subtitles were loaded
        if subtitle_file or subtitle_track:
            criteria_met += 1
            if subtitle_file:
                feedback_parts.append(f"✅ Subtitle file: {subtitle_file}")
            if subtitle_track:
                feedback_parts.append(f"✅ Subtitle track: {subtitle_track}")
        else:
            feedback_parts.append("⚠️ No subtitle file or track found")

        # Check if subtitles are enabled
        if subtitle_enabled:
            criteria_met += 1
            feedback_parts.append("✅ Subtitles enabled")
        else:
            feedback_parts.append("❌ Subtitles not enabled")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading subtitles result: {str(e)}"}

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_subtitles_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
