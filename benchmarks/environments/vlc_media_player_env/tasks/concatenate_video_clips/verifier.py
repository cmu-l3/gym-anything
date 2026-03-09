#!/usr/bin/env python3
"""
Verifier for Concatenate Video Clips task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    verify_video_duration,
    verify_video_resolution,
    verify_video_codec,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_concatenate_video_clips(traj, env_info, task_info):
    """
    Verify concatenate video clips task completion.
    
    Checks:
    1. Merged output video file exists
    2. Video duration is approximately 40 seconds (4 clips × 10s each)
    3. Video has correct resolution (1280×720)
    4. Video codec is H.264/AVC
    5. File size is reasonable (indicates successful merge, not empty file)
    
    Success requires meeting at least 75% of criteria.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Check if output file was found
    temp_not_found = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_merged_output_not_found.txt", temp_not_found.name)
        os.unlink(temp_not_found.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Merged output video file not found at expected location"
        }
    except Exception:
        # File doesn't exist, which is good - means output was found
        pass
    
    # Criterion 1: Check for merged video file and parse it
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_merged_output.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Merged video not found or invalid: {error}"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Output file exists")
    
    video_data = file_info.get('data', {})
    
    # Log video info for debugging
    logger.info(f"Video data: {video_data}")
    
    # Criterion 2: Check video duration (should be ~40 seconds for 4×10s clips)
    duration = video_data.get('duration', 0)
    expected_duration = 40.0
    tolerance = 3.0  # ±3 seconds tolerance
    
    if duration > 0:
        if abs(duration - expected_duration) <= tolerance:
            criteria_met += 1
            feedback_parts.append(f"✅ Duration correct: {duration:.1f}s (expected ~{expected_duration}s)")
        elif duration >= 30 and duration <= 50:
            # Partial credit if duration is in reasonable range
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Duration close: {duration:.1f}s (expected ~{expected_duration}s)")
        else:
            feedback_parts.append(f"❌ Duration incorrect: {duration:.1f}s (expected ~{expected_duration}s)")
    else:
        feedback_parts.append("❌ Duration not detected (file may be corrupted)")
    
    # Criterion 3: Check resolution (should be 1280×720)
    width = video_data.get('width', 0)
    height = video_data.get('height', 0)
    expected_width = 1280
    expected_height = 720
    
    if width == expected_width and height == expected_height:
        criteria_met += 1
        feedback_parts.append(f"✅ Resolution correct: {width}×{height}")
    elif width > 0 and height > 0:
        feedback_parts.append(f"⚠️ Resolution unexpected: {width}×{height} (expected {expected_width}×{expected_height})")
    else:
        feedback_parts.append("❌ Resolution not detected")
    
    # Criterion 4: Check codec (should be H.264/AVC)
    codec = video_data.get('codec', '').lower()
    if 'h264' in codec or 'avc' in codec:
        criteria_met += 1
        feedback_parts.append(f"✅ Codec correct: {video_data.get('codec')}")
    elif codec:
        feedback_parts.append(f"⚠️ Codec unexpected: {video_data.get('codec')} (expected H.264)")
    else:
        feedback_parts.append("❌ Codec not detected")
    
    # Additional check: File size should be reasonable (>500KB for 40s video)
    size_bytes = video_data.get('size_bytes', 0)
    size_kb = size_bytes / 1024
    
    if size_kb < 500:
        feedback_parts.append(f"⚠️ File size small: {size_kb:.0f}KB (may indicate failed merge)")
    else:
        feedback_parts.append(f"File size: {size_kb:.0f}KB")
    
    # Cleanup
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_concat_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        
        logger.info(f"Completion marker content:\n{content}")
        os.unlink(temp_marker.name)
    except Exception as e:
        feedback_parts.append("⚠️ Completion marker not found")
        logger.warning(f"Could not read completion marker: {e}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }