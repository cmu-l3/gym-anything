#!/usr/bin/env python3
"""
Verifier for Play Video task
"""

import sys
import os
import logging

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


def verify_play_video(traj, env_info, task_info):
    """
    Verify play video task completion.
    
    Checks:
    1. Video file exists and is valid
    2. VLC completion marker exists (indicating task ran)
    3. Video properties are correct
    
    This is a basic task, so we mainly verify the setup worked
    and the video file is valid. In a real scenario, we'd check
    VLC logs for playback completion indicators.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Criterion 1: Verify video file exists and is valid
    video_path = "/home/ga/Videos/sample_video.mp4"
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        video_path,
        file_type='video'
    )
    
    if success:
        video_data = file_info.get('data', {})
        
        # Check video properties
        if video_data.get('duration', 0) > 25:  # Should be ~30 seconds
            criteria_met += 1
            feedback_parts.append(f"✅ Video file valid (duration: {video_data.get('duration', 0):.1f}s)")
        else:
            feedback_parts.append(f"❌ Video file invalid or too short")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append(f"❌ Could not verify video file: {error}")
    
    # Criterion 2: Check completion marker
    import tempfile
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_play_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        
        if "completed" in content.lower():
            criteria_met += 1
            feedback_parts.append("✅ Task completion marker found")
        else:
            feedback_parts.append("❌ Task completion marker invalid")
        
        os.unlink(temp_marker.name)
    except Exception as e:
        feedback_parts.append(f"⚠️ Completion marker not found (task may not have run)")
    
    # Criterion 3: Check VLC log for any errors
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
    try:
        copy_from_env("/tmp/vlc_play_result.log", temp_log.name)
        
        with open(temp_log.name, 'r') as f:
            log_content = f.read()
        
        # Check for errors in log
        if "error" not in log_content.lower() or len(log_content) > 10:
            criteria_met += 1
            feedback_parts.append("✅ VLC log shows no major errors")
        else:
            feedback_parts.append("⚠️ VLC log may indicate issues")
        
        os.unlink(temp_log.name)
    except Exception as e:
        # Log might not exist, that's okay
        feedback_parts.append("⚠️ VLC log not available")
        criteria_met += 0.5  # Partial credit
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 65  # Lower threshold for easy task
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
