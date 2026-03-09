#!/usr/bin/env python3
"""
Verifier for Test Capture Devices task

Verifies that a valid capture device recording was created with:
- Both video and audio streams
- Appropriate duration (3-10 seconds, target ~5s)
- Reasonable quality (valid codecs, proper resolution)
"""

import sys
import os
import logging
import tempfile
import glob

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


def verify_test_capture_devices(traj, env_info, task_info):
    """
    Verify test capture devices task completion.
    
    Checks:
    1. Recording file exists (recent video file in ~/Videos/)
    2. Video stream present with valid codec
    3. Audio stream present with valid codec
    4. Duration is appropriate (3-10 seconds, target: ~5s)
    5. Quality indicators (resolution, file size)
    
    Pass threshold: 85% (requires both A/V streams with correct duration)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Try to find and copy the recording file
    # Try multiple extensions
    recording_found = False
    file_info = None
    temp_dir = None
    
    for ext in ['mp4', 'avi', 'mkv', 'mov']:
        try:
            container_path = f"/tmp/vlc_capture_recording.{ext}"
            success, file_info, error = setup_verification_environment(
                copy_from_env,
                container_path,
                file_type='video'
            )
            
            if success:
                recording_found = True
                temp_dir = file_info.get('temp_dir')
                logger.info(f"Found recording with extension: {ext}")
                break
        except Exception as e:
            logger.debug(f"Could not find recording with extension {ext}: {e}")
            continue
    
    if not recording_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ No recording file found in ~/Videos/ - agent may not have completed recording"
        }
    
    # Criterion 1: Recording file exists (already verified above)
    criteria_met += 1
    feedback_parts.append("✅ Recording file exists")
    
    video_data = file_info.get('data', {})
    filepath = file_info.get('filepath', '')
    
    # Criterion 2: Check video stream present
    video_codec = video_data.get('codec', '')
    video_width = video_data.get('width', 0)
    video_height = video_data.get('height', 0)
    
    if video_codec and video_width > 0 and video_height > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ Video stream present ({video_codec}, {video_width}x{video_height})")
    else:
        feedback_parts.append("❌ No valid video stream detected")
    
    # Criterion 3: Check audio stream present
    # Need to separately check audio stream
    audio_valid = False
    try:
        audio_info = get_audio_info(filepath)
        audio_codec = audio_info.get('codec', '')
        
        if audio_codec and 'error' not in audio_info:
            criteria_met += 1
            sample_rate = audio_info.get('sample_rate', 0)
            channels = audio_info.get('channels', 0)
            feedback_parts.append(f"✅ Audio stream present ({audio_codec}, {sample_rate}Hz, {channels}ch)")
            audio_valid = True
        else:
            feedback_parts.append("❌ No valid audio stream detected")
    except Exception as e:
        logger.warning(f"Could not verify audio stream: {e}")
        feedback_parts.append("⚠️  Audio stream verification inconclusive")
    
    # Criterion 4: Check duration (3-10 seconds, target ~5s)
    duration = video_data.get('duration', 0)
    
    if 3.0 <= duration <= 10.0:
        # Give full credit for acceptable range
        if 4.0 <= duration <= 6.0:
            criteria_met += 1
            feedback_parts.append(f"✅ Perfect duration ({duration:.1f}s, target: 5s)")
        else:
            criteria_met += 0.8  # Slight deduction for being outside ideal range
            feedback_parts.append(f"✅ Acceptable duration ({duration:.1f}s, target: 5s)")
    elif 2.0 <= duration < 3.0:
        criteria_met += 0.5
        feedback_parts.append(f"⚠️  Recording slightly too short ({duration:.1f}s)")
    elif 10.0 < duration <= 15.0:
        criteria_met += 0.6
        feedback_parts.append(f"⚠️  Recording too long ({duration:.1f}s, did you forget to stop?)")
    else:
        feedback_parts.append(f"❌ Duration out of acceptable range ({duration:.1f}s, expected 3-10s)")
    
    # Criterion 5: Quality indicators (resolution and file size)
    file_size_kb = os.path.getsize(filepath) / 1024
    
    # Minimum quality thresholds
    min_width = 160
    min_height = 120
    min_file_size_kb = 50
    
    quality_ok = (
        video_width >= min_width and
        video_height >= min_height and
        file_size_kb >= min_file_size_kb
    )
    
    if quality_ok:
        criteria_met += 1
        feedback_parts.append(f"✅ Quality acceptable (resolution: {video_width}x{video_height}, size: {file_size_kb:.1f}KB)")
    else:
        quality_issues = []
        if video_width < min_width or video_height < min_height:
            quality_issues.append(f"low resolution ({video_width}x{video_height})")
        if file_size_kb < min_file_size_kb:
            quality_issues.append(f"small file ({file_size_kb:.1f}KB)")
        
        feedback_parts.append(f"⚠️  Quality issues: {', '.join(quality_issues)}")
    
    # Cleanup
    if temp_dir:
        cleanup_verification_environment(temp_dir)
    
    # Calculate score
    # Use float for more precise scoring with partial credits
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 85  # High threshold since this is important functionality
    
    # Add summary feedback
    filename = os.path.basename(filepath) if filepath else "unknown"
    summary = f"Recording: {filename}"
    feedback = summary + " | " + " | ".join(feedback_parts)
    
    # Add helpful hints if failed
    if not passed:
        hints = []
        if not video_codec:
            hints.append("Ensure video device was selected in capture dialog")
        if not audio_valid:
            hints.append("Ensure audio device was selected in capture dialog")
        if duration < 3.0:
            hints.append("Recording needs to be at least 3 seconds long")
        elif duration > 10.0:
            hints.append("Remember to stop recording after ~5 seconds")
        
        if hints:
            feedback += " || Hints: " + "; ".join(hints)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }