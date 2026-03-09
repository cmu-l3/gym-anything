#!/usr/bin/env python3
"""
Verifier for Crop Video Borders task

This verifier checks that:
1. The output video file exists
2. The resolution is correct (1240x580 after cropping from 1280x720)
3. The video is valid (correct codec, reasonable duration and file size)
4. Duration is preserved from the original video
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


def verify_crop_video_borders(traj, env_info, task_info):
    """
    Verify crop video borders task completion.
    
    Checks:
    1. Output video file exists
    2. Resolution is exactly 1240x580 (cropped from 1280x720)
    3. Video has valid codec (H.264) and reasonable file size
    4. Duration is preserved from original (~15 seconds)
    
    Args:
        traj: Trajectory data
        env_info: Environment information including copy_from_env function
        task_info: Task information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available for verification"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Expected values
    expected_width = 1240
    expected_height = 580
    expected_duration = 15.0
    duration_tolerance = 1.0  # ±1 second
    min_file_size_kb = 100  # Minimum reasonable file size
    
    # Try to copy and verify the cropped video
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_crop_borders_output.mp4",
        file_type='video'
    )
    
    if not success:
        # Video file not found
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Cropped video file not found: {error}"
        }
    
    # Criterion 1: File exists
    criteria_met += 1
    feedback_parts.append("✅ Cropped video file exists")
    
    # Get video data
    video_data = file_info.get('data', {})
    
    if 'error' in video_data:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 25,
            "feedback": f"❌ Error analyzing video: {video_data['error']}"
        }
    
    # Extract video properties
    actual_width = video_data.get('width', 0)
    actual_height = video_data.get('height', 0)
    actual_duration = video_data.get('duration', 0)
    codec = video_data.get('codec', '').lower()
    file_size_bytes = video_data.get('size_bytes', 0)
    file_size_kb = file_size_bytes / 1024
    
    logger.info(f"Video properties: {actual_width}x{actual_height}, "
                f"duration={actual_duration:.1f}s, codec={codec}, "
                f"size={file_size_kb:.1f}KB")
    
    # Criterion 2: Correct resolution (most important)
    if actual_width == expected_width and actual_height == expected_height:
        criteria_met += 1
        feedback_parts.append(f"✅ Resolution correct: {actual_width}x{actual_height}")
    else:
        feedback_parts.append(
            f"❌ Resolution incorrect: {actual_width}x{actual_height} "
            f"(expected: {expected_width}x{expected_height})"
        )
        # This is a critical failure - the crop was not applied correctly
        cleanup_verification_environment(file_info.get('temp_dir'))
        score = int((criteria_met / total_criteria) * 100)
        feedback = " | ".join(feedback_parts)
        return {
            "passed": False,
            "score": score,
            "feedback": feedback
        }
    
    # Criterion 3: Valid video file (codec and file size)
    codec_valid = 'h264' in codec or 'avc' in codec  # H.264 is also known as AVC
    size_valid = file_size_kb > min_file_size_kb
    
    if codec_valid and size_valid:
        criteria_met += 1
        feedback_parts.append(
            f"✅ Video valid: codec={codec}, size={file_size_kb:.1f}KB"
        )
    else:
        if not codec_valid:
            feedback_parts.append(f"⚠️ Unexpected codec: {codec} (expected: h264)")
        if not size_valid:
            feedback_parts.append(
                f"⚠️ File too small: {file_size_kb:.1f}KB (min: {min_file_size_kb}KB)"
            )
    
    # Criterion 4: Duration preserved
    duration_diff = abs(actual_duration - expected_duration)
    
    if duration_diff <= duration_tolerance:
        criteria_met += 1
        feedback_parts.append(f"✅ Duration preserved: {actual_duration:.1f}s")
    else:
        feedback_parts.append(
            f"⚠️ Duration changed: {actual_duration:.1f}s "
            f"(expected: ~{expected_duration:.1f}s)"
        )
    
    # Check if audio stream exists (bonus check, not counted in score)
    audio_info = get_audio_info(file_info.get('filepath', ''))
    if 'error' not in audio_info:
        feedback_parts.append("✅ Audio preserved")
    else:
        feedback_parts.append("⚠️ Audio stream missing")
    
    # Clean up temporary files
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need 3 out of 4 criteria to pass
    
    # Construct feedback message
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        feedback = f"✅ PASSED ({score}%) - {feedback}"
    else:
        feedback = f"❌ FAILED ({score}%) - {feedback}"
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
