#!/usr/bin/env python3
"""
Verifier for Concatenate Split Recordings task

Checks:
1. Output file exists
2. Duration matches sum of input durations (±3s tolerance)
3. Content is complete (at least 80% of expected duration)
4. Quality preserved (resolution and codec correct)
5. File is playable
"""

import sys
import os
import logging

# Use relative path to utils folder (verification runs on host)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_concatenate_split_recordings(traj, env_info, task_info):
    """
    Verify concatenate split recordings task completion.
    
    Multi-criteria verification:
    1. Output file exists and is accessible
    2. Duration matches expected total (sum of parts ±3s)
    3. Content completeness (at least 80% of expected)
    4. Quality preservation (resolution, codec)
    5. File playability
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Expected values
    expected_duration = 60.0  # 3 parts x 20 seconds each
    expected_width = 1280
    expected_height = 720
    tolerance = 3.0  # ±3 seconds
    min_duration_percent = 0.80  # At least 80% of expected
    
    # Criterion 1: Check if output file exists
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_concatenated_output.mp4",
        file_type='video'
    )
    
    if not success:
        # Check if missing marker exists
        import tempfile
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_concatenated_output_missing.txt", temp_marker.name)
            os.unlink(temp_marker.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Output file not created - concatenation did not complete"
            }
        except Exception:
            pass
        
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Output file not found: {error}"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Output file exists")
    
    video_data = file_info.get('data', {})
    
    # Check if video info is valid
    if 'error' in video_data:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 20,
            "feedback": f"❌ Output file exists but cannot be analyzed: {video_data['error']}"
        }
    
    # Extract video properties
    actual_duration = video_data.get('duration', 0)
    actual_width = video_data.get('width', 0)
    actual_height = video_data.get('height', 0)
    actual_codec = video_data.get('codec', 'unknown')
    
    logger.info(f"Output video: {actual_duration:.1f}s, {actual_width}x{actual_height}, codec: {actual_codec}")
    
    # Criterion 2: Duration accuracy (±3s tolerance)
    duration_diff = abs(actual_duration - expected_duration)
    if duration_diff <= tolerance:
        criteria_met += 1
        feedback_parts.append(f"✅ Duration correct: {actual_duration:.1f}s (expected ~{expected_duration:.0f}s, diff: {duration_diff:.1f}s)")
    elif actual_duration > 0:
        feedback_parts.append(f"⚠️ Duration mismatch: {actual_duration:.1f}s (expected ~{expected_duration:.0f}s, diff: {duration_diff:.1f}s)")
    else:
        feedback_parts.append("❌ Duration is zero or invalid")
    
    # Criterion 3: Content completeness (at least 80% of expected)
    min_acceptable_duration = expected_duration * min_duration_percent
    if actual_duration >= min_acceptable_duration:
        criteria_met += 1
        completeness_percent = (actual_duration / expected_duration) * 100
        feedback_parts.append(f"✅ Content complete: {completeness_percent:.0f}% of expected duration")
    else:
        completeness_percent = (actual_duration / expected_duration) * 100
        feedback_parts.append(f"❌ Content incomplete: only {completeness_percent:.0f}% of expected duration (may be missing parts)")
    
    # Criterion 4: Quality preservation - Resolution
    resolution_ok = (actual_width == expected_width and actual_height == expected_height)
    if resolution_ok:
        criteria_met += 1
        feedback_parts.append(f"✅ Resolution preserved: {actual_width}x{actual_height}")
    elif actual_width > 0 and actual_height > 0:
        # Resolution exists but doesn't match - partial credit
        feedback_parts.append(f"⚠️ Resolution changed: {actual_width}x{actual_height} (expected {expected_width}x{expected_height})")
    else:
        feedback_parts.append("❌ Resolution invalid")
    
    # Criterion 5: Playability - check codec and basic validity
    valid_codecs = ['h264', 'h265', 'hevc', 'mpeg4', 'vp8', 'vp9']
    codec_valid = any(codec in actual_codec.lower() for codec in valid_codecs)
    
    if codec_valid and actual_duration > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ File playable: codec={actual_codec}")
    elif actual_codec != 'unknown':
        feedback_parts.append(f"⚠️ Codec present but unusual: {actual_codec}")
    else:
        feedback_parts.append("❌ File may not be playable (codec unknown)")
    
    # Cleanup
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 4 out of 5 criteria
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary = f"Score: {criteria_met}/{total_criteria} criteria met"
    feedback = f"{summary} | {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "total_criteria": total_criteria,
            "actual_duration": actual_duration,
            "expected_duration": expected_duration,
            "duration_diff": duration_diff,
            "resolution": f"{actual_width}x{actual_height}",
            "codec": actual_codec
        }
    }