#!/usr/bin/env python3
"""
Verifier for Capture Stream Recording task
Verifies that VLC successfully recorded a network stream to a local file
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


def verify_capture_stream_recording(traj, env_info, task_info):
    """
    Verify that network stream was successfully recorded.
    
    Checks:
    1. Recording file exists and is accessible
    2. File has reasonable size (>500 KB indicates actual content)
    3. Video has valid codec
    4. Duration is at least 25 seconds (allowing for startup latency)
    5. Resolution is valid (video not corrupted)
    
    Returns:
        dict with 'passed', 'score', 'feedback'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Pre-check: Was recording file found at all?
    temp_not_found = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_stream_recording_not_found.txt", temp_not_found.name)
        os.unlink(temp_not_found.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Recording file not found. Task may not have been attempted or output path was incorrect."
        }
    except Exception:
        # File doesn't exist means recording was found - good!
        pass
    
    # Criterion 1: Setup and copy recording file
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_stream_recording.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Recording file not accessible: {error}"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Recording file exists")
    
    video_data = file_info.get('data', {})
    
    # Check for parse errors
    if 'error' in video_data:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 20,
            "feedback": f"❌ Recording appears corrupted or invalid: {video_data['error']}"
        }
    
    # Criterion 2: File size check (should be > 500 KB for ~30s of video)
    file_size_bytes = video_data.get('size_bytes', 0)
    file_size_kb = file_size_bytes / 1024
    
    if file_size_kb > 500:
        criteria_met += 1
        feedback_parts.append(f"✅ File size adequate ({file_size_kb:.0f} KB)")
    elif file_size_kb > 200:
        criteria_met += 0.5  # Partial credit
        feedback_parts.append(f"⚠️ File size small ({file_size_kb:.0f} KB, expected >500 KB)")
    else:
        feedback_parts.append(f"❌ File too small ({file_size_kb:.0f} KB) - recording likely failed or is empty")
        cleanup_verification_environment(file_info.get('temp_dir'))
        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 3: Video codec check
    codec = video_data.get('codec', '').lower()
    if codec and codec != 'unknown':
        criteria_met += 1
        feedback_parts.append(f"✅ Valid video codec ({codec})")
    else:
        feedback_parts.append("❌ No valid video codec detected")
    
    # Criterion 4: Duration check (at least 25 seconds, allowing for startup latency)
    duration = video_data.get('duration', 0)
    
    if duration >= 25.0:
        criteria_met += 1
        feedback_parts.append(f"✅ Duration sufficient ({duration:.1f}s)")
    elif duration >= 15.0:
        criteria_met += 0.5  # Partial credit for some recording
        feedback_parts.append(f"⚠️ Duration short ({duration:.1f}s, expected ≥25s)")
    elif duration > 0:
        feedback_parts.append(f"❌ Duration too short ({duration:.1f}s, expected ≥25s)")
    else:
        feedback_parts.append("❌ Duration could not be determined")
    
    # Criterion 5: Resolution check (ensure video is valid, not corrupted)
    width = video_data.get('width', 0)
    height = video_data.get('height', 0)
    
    if width >= 100 and height >= 100:
        criteria_met += 1
        feedback_parts.append(f"✅ Valid resolution ({width}x{height})")
    elif width > 0 and height > 0:
        criteria_met += 0.5  # Partial credit for some resolution
        feedback_parts.append(f"⚠️ Low resolution ({width}x{height})")
    else:
        feedback_parts.append(f"❌ Invalid resolution ({width}x{height})")
    
    # Check completion marker (informational, not scored)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_stream_capture_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        os.unlink(temp_marker.name)
        
        if 'completed' in content.lower():
            feedback_parts.append("✅ Task completed")
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Cleanup temporary files
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate score (criteria_met can have 0.5 increments, so convert carefully)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need 70% to pass (3.5/5 criteria)
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary message
    if passed:
        summary = f"✅ Stream recording successful! Captured {duration:.1f}s of video ({file_size_kb:.0f} KB)"
    else:
        summary = f"❌ Stream recording incomplete or invalid (score: {score}%)"
    
    feedback = summary + " | " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
