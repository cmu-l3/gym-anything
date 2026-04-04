#!/usr/bin/env python3
"""
Verifier for Capture Desktop Lecture task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_capture_desktop(traj, env_info, task_info):
    """
    Verify capture desktop lecture task completion.
    
    Checks:
    1. Recording file exists
    2. Duration is at least 8 seconds (target 10-15s)
    3. Valid video format with proper codec
    4. Reasonable file size for recording duration
    5. Video is playable (frames extractable)
    6. Desktop capture properties (resolution)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Check for recording file
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_desktop_recording.mp4",
        file_type='video'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Desktop recording not found: {error}"}
    
    criteria_met += 1
    feedback_parts.append("✅ Recording file exists")
    
    video_data = file_info.get('data', {})
    
    # Criterion 2: Check duration (minimum 8 seconds, target 10-15s)
    duration = video_data.get('duration', 0)
    if duration >= 8.0:
        criteria_met += 1
        if duration <= 20.0:  # Ideal range with some tolerance
            feedback_parts.append(f"✅ Duration perfect: {duration:.1f}s")
        else:
            feedback_parts.append(f"✅ Duration acceptable: {duration:.1f}s (longer than expected)")
    else:
        feedback_parts.append(f"❌ Duration too short: {duration:.1f}s (minimum 8s)")
    
    # Criterion 3: Check video properties (codec)
    codec = video_data.get('codec', '')
    if codec:
        criteria_met += 1
        feedback_parts.append(f"✅ Valid codec: {codec}")
    else:
        feedback_parts.append("❌ Video codec not detected")
    
    # Criterion 4: Check file size is reasonable
    # Desktop capture: roughly 50-1000 KB per second depending on settings
    file_size_kb = video_data.get('size_bytes', 0) / 1024
    if duration > 0:
        kb_per_sec = file_size_kb / duration
        
        if 50 <= kb_per_sec <= 2000:  # Reasonable range for screen capture
            criteria_met += 1
            feedback_parts.append(f"✅ File size reasonable: {file_size_kb:.0f}KB ({kb_per_sec:.0f}KB/s)")
        elif file_size_kb > 100:  # At least it's not empty
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ File size unusual: {file_size_kb:.0f}KB ({kb_per_sec:.0f}KB/s)")
        else:
            feedback_parts.append(f"❌ File too small: {file_size_kb:.0f}KB")
    else:
        if file_size_kb > 100:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Cannot assess size/duration ratio: {file_size_kb:.0f}KB")
        else:
            feedback_parts.append(f"❌ File too small: {file_size_kb:.0f}KB")
    
    # Criterion 5: Check video is playable (has valid streams)
    width = video_data.get('width', 0)
    height = video_data.get('height', 0)
    
    if width > 0 and height > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ Video playable: {width}x{height}")
    else:
        feedback_parts.append("❌ Video may be corrupted")
    
    # Criterion 6: Check desktop capture properties
    # Desktop captures should have reasonable resolution (at least 800x600)
    if width >= 800 and height >= 600:
        criteria_met += 1
        
        # Give extra positive feedback for full desktop resolutions
        if width >= 1920 or height >= 1080:
            feedback_parts.append(f"✅ Full desktop captured: {width}x{height}")
        elif width >= 1280 or height >= 720:
            feedback_parts.append(f"✅ HD desktop captured: {width}x{height}")
        else:
            feedback_parts.append(f"✅ Valid desktop capture: {width}x{height}")
    elif width > 0:
        feedback_parts.append(f"⚠️ Resolution low for desktop capture: {width}x{height}")
    else:
        feedback_parts.append("❌ Cannot verify desktop capture properties")
    
    # Optional: Check frame rate is reasonable for desktop capture (5-30 fps)
    fps = video_data.get('fps', 0)
    if fps > 0:
        if 5 <= fps <= 30:
            feedback_parts.append(f"Frame rate: {fps:.1f}fps (good for desktop)")
        else:
            feedback_parts.append(f"Frame rate: {fps:.1f}fps (unusual)")
    
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_capture_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "yes" in marker_content:
            feedback_parts.append("✅ Task completed")
        
        os.unlink(temp_marker.name)
    except Exception as e:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Use ceiling for partial credits
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    # Log detailed results
    logger.info(f"Verification results: {criteria_met}/{total_criteria} criteria met")
    logger.info(f"Score: {score}% | Passed: {passed}")
    logger.info(f"Feedback: {feedback}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }