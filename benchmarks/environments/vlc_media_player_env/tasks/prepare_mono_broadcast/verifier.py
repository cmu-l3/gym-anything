#!/usr/bin/env python3
"""
Verifier for Prepare Mono Broadcast task
Checks that stereo audio was properly converted to mono format
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that the audio file has been properly converted to mono.
    
    Checks:
    1. Converted audio file exists
    2. Audio is mono (1 channel, not 2)
    3. Audio has valid content (reasonable duration and size)
    
    Args:
        traj: The trajectory of actions taken
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Check if file not found marker exists
    temp_not_found = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_mono_broadcast_not_found.txt", temp_not_found.name)
        os.unlink(temp_not_found.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Output file not found at /home/ga/Music/broadcast_ready/listener_recording_mono.wav"
        }
    except Exception:
        # File not found marker doesn't exist, which is good
        pass
    
    # Criterion 1, 2, 3: Copy and analyze the output file
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_mono_broadcast.wav",
        file_type='audio'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to analyze output file: {error}"
        }
    
    try:
        audio_data = file_info['data']
        
        # Criterion 1: File exists (implicit if we got here)
        criteria_met += 1
        feedback_parts.append("✅ Converted audio file exists")
        
        # Criterion 2: Verify mono (1 channel)
        channels = audio_data.get('channels', 0)
        if channels == 1:
            criteria_met += 1
            feedback_parts.append(f"✅ Audio is mono (1 channel)")
        elif channels == 2:
            feedback_parts.append(f"❌ Audio is still stereo (2 channels) - conversion not performed correctly")
        elif channels == 0:
            feedback_parts.append(f"❌ Could not detect audio channels - file may be corrupt")
        else:
            feedback_parts.append(f"⚠️ Unexpected channel count: {channels}")
        
        # Criterion 3: Verify audio has content (duration and size)
        duration = audio_data.get('duration', 0)
        size_kb = audio_data.get('size_bytes', 0) / 1024
        
        if duration >= 25:  # Should be ~30 seconds, allow some tolerance
            criteria_met += 1
            feedback_parts.append(f"✅ Audio has valid content ({duration:.1f}s, {size_kb:.1f}KB)")
        elif duration > 0:
            feedback_parts.append(f"⚠️ Audio is shorter than expected ({duration:.1f}s)")
            criteria_met += 0.5  # Partial credit
        else:
            feedback_parts.append(f"❌ Audio file appears empty or corrupt")
        
        # Additional checks for feedback (not scored)
        codec = audio_data.get('codec', '').lower()
        sample_rate = audio_data.get('sample_rate', 0)
        
        if codec:
            feedback_parts.append(f"Codec: {codec}")
        
        if sample_rate > 0:
            if sample_rate < 22050:
                feedback_parts.append(f"⚠️ Low sample rate ({sample_rate}Hz) - consider 44.1kHz+")
            else:
                feedback_parts.append(f"Sample rate: {sample_rate}Hz")
        
        # Check if format is WAV (preferred for broadcast)
        format_name = audio_data.get('format', '').lower()
        if 'wav' in format_name or 'pcm' in codec:
            feedback_parts.append("✅ Format: WAV (broadcast-ready)")
        else:
            feedback_parts.append(f"ℹ️ Format: {format_name}")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
        
    except Exception as e:
        cleanup_verification_environment(file_info.get('temp_dir'))
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_mono_broadcast_completed.txt", temp_marker.name)
        # Don't add to criteria_met, just informational
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score (out of 100)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need at least 2/3 criteria (file exists + mono)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
