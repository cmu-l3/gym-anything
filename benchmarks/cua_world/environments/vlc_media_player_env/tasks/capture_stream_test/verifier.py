#!/usr/bin/env python3
"""
Verifier for Capture Stream Test task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_capture_stream_test(traj, env_info, task_info):
    """
    Verify capture stream test task completion.
    
    Checks:
    1. Recording file exists and is parseable
    2. Duration is within expected range (15-30 seconds)
    3. Video track is valid (codec, resolution)
    4. Audio track is valid (codec exists)
    5. File size is reasonable (> 200 KB)
    
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Check if recording was not found marker exists
    temp_not_found = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_stream_capture_not_found.txt", temp_not_found.name)
        os.unlink(temp_not_found.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Recording file not found - stream may not have been opened or recording not started"
        }
    except Exception:
        # File doesn't exist, which is good - means recording was found
        pass
    
    # Setup verification environment (copy and parse video file)
    output_path = "/tmp/vlc_stream_capture.mp4"
    
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        output_path,
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Recording file not found or invalid: {error}"
        }
    
    try:
        # Criterion 1: File exists and is parseable (already verified by setup)
        criteria_met += 1
        feedback_parts.append("✅ Recording file exists")
        
        video_data = file_info['data']
        
        # Criterion 2: Check video track exists
        if 'codec' not in video_data or not video_data['codec']:
            feedback_parts.append("❌ No valid video track found in recording")
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {
                "passed": False,
                "score": 20,
                "feedback": " | ".join(feedback_parts)
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Video codec: {video_data['codec']}")
        
        # Criterion 3: Check duration is reasonable (15-30 seconds)
        if 'duration' not in video_data:
            feedback_parts.append("❌ Could not determine recording duration")
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {
                "passed": False,
                "score": 40,
                "feedback": " | ".join(feedback_parts)
            }
        
        duration = video_data['duration']
        
        if duration < 15.0:
            feedback_parts.append(f"⚠️ Recording too short: {duration:.1f}s (minimum 15s)")
        elif duration > 30.0:
            feedback_parts.append(f"⚠️ Recording too long: {duration:.1f}s (maximum 30s)")
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ Duration: {duration:.1f}s (valid range)")
        
        # Criterion 4: Check audio track exists
        # Re-analyze specifically for audio
        audio_info = get_audio_info(video_data['filepath'])
        
        if 'error' in audio_info or 'codec' not in audio_info or not audio_info['codec']:
            feedback_parts.append("⚠️ No valid audio track found - stream may have no audio")
        else:
            criteria_met += 1
            sample_rate = audio_info.get('sample_rate', 'unknown')
            feedback_parts.append(f"✅ Audio codec: {audio_info['codec']} ({sample_rate}Hz)")
        
        # Criterion 5: Check file size is reasonable (> 200 KB)
        size_kb = video_data.get('size_bytes', 0) / 1024
        
        if size_kb < 200:
            feedback_parts.append(f"⚠️ Recording file small: {size_kb:.1f} KB (may be incomplete)")
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ File size: {size_kb:.1f} KB")
        
        # Check video resolution is valid
        width = video_data.get('width', 0)
        height = video_data.get('height', 0)
        
        if width == 0 or height == 0:
            feedback_parts.append("⚠️ Invalid video resolution")
        else:
            feedback_parts.append(f"Resolution: {width}x{height}")
        
        # All checks complete
        cleanup_verification_environment(file_info.get('temp_dir'))
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    # Add overall assessment
    if passed:
        feedback = "✅ Stream capture successful! " + feedback
    elif score >= 60:
        feedback = "⚠️ Stream capture partially successful. " + feedback
    else:
        feedback = "❌ Stream capture failed. " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }