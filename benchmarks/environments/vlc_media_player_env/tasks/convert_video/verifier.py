#!/usr/bin/env python3
"""
Verifier for Convert Video task
"""

import sys
import os
import logging

# Add utils directory to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))


from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_convert_video(traj, env_info, task_info):
    """
    Verify convert video task completion.
    
    Checks:
    1. Converted video file exists
    2. Video has correct format/codec
    3. Video is valid and playable
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Check for converted video file
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_converted_video.mp4",
        file_type='video'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Converted video not found: {error}"}
    
    criteria_met += 1
    feedback_parts.append("✅ Converted video file exists")
    
    video_data = file_info.get('data', {})
    
    # Criterion 2: Check video properties
    if video_data.get('codec'):
        criteria_met += 1
        feedback_parts.append(f"✅ Video codec: {video_data.get('codec')}")
    else:
        feedback_parts.append("⚠️ Video codec not detected")
    
    # Criterion 3: Check video is valid (has duration, resolution)
    if video_data.get('duration', 0) > 0 and video_data.get('width', 0) > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ Video valid ({video_data.get('duration', 0):.1f}s, {video_data.get('resolution', 'unknown')})")
    else:
        feedback_parts.append("❌ Video may be corrupted")
    
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
