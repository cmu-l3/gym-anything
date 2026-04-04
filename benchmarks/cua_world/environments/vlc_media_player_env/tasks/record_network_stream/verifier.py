#!/usr/bin/env python3
"""
Verifier for Record Network Stream task
"""

import sys
import os
import logging

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recording(traj, env_info, task_info):
    """
    Verify VLC network stream recording task.
    
    Checks:
    1. Recording file exists at expected location
    2. File size > 100 KB (non-empty, meaningful content)
    3. File is a valid video container (MP4)
    4. Video has valid codec (H.264 or compatible)
    5. Recording duration > 5 seconds (sufficient capture)
    
    Scoring:
    - 100%: Perfect recording (all criteria met)
    - 85-99%: Good recording with minor issues
    - 70-84%: Acceptable recording with some issues
    - 50-69%: Partial success (file exists but problems)
    - 0-49%: Failed (no file or critically flawed)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Expected thresholds
    min_size_kb = 100
    min_duration_sec = 5.0
    expected_codecs = ['h264', 'x264', 'avc', 'hevc', 'h265', 'mpeg4', 'xvid']
    
    # Check if recording was not found marker exists
    import tempfile
    not_found_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_recording_not_found.txt", not_found_marker.name)
        os.unlink(not_found_marker.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Recording file was not created - check if Convert/Save dialog was used correctly"
        }
    except Exception:
        # Marker doesn't exist, proceed with normal verification
        pass
    
    # Copy and analyze recorded video
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_recorded_stream.mp4",
        file_type='video'
    )
    
    if not success:
        logger.error(f"Failed to copy recording: {error}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Recording verification failed: {error}"
        }
    
    try:
        # Criterion 1: File exists (implicit if we got here)
        criteria_met += 1
        feedback_parts.append("✅ Recording file created")
        
        data = file_info.get('data', {})
        
        # Check for errors in video info
        if 'error' in data:
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {
                "passed": False,
                "score": 20,
                "feedback": f"❌ Recording file is invalid or corrupted: {data['error']}"
            }
        
        # Criterion 2: File size check
        size_bytes = data.get('size_bytes', 0)
        size_kb = size_bytes / 1024
        
        if size_kb >= min_size_kb:
            criteria_met += 1
            feedback_parts.append(f"✅ File size OK ({size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"❌ File too small: {size_kb:.1f} KB (expected > {min_size_kb} KB)")
        
        # Criterion 3: Valid container format
        format_name = data.get('format', '').lower()
        if 'mp4' in format_name or 'mov' in format_name or 'avi' in format_name:
            criteria_met += 1
            feedback_parts.append(f"✅ Valid container format ({format_name})")
        elif format_name:
            # Some format detected, partial credit
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Unexpected format: {format_name}")
        else:
            feedback_parts.append("❌ Could not detect container format")
        
        # Criterion 4: Video codec check
        codec = data.get('codec', '').lower()
        codec_ok = any(exp in codec for exp in expected_codecs) if codec else False
        
        if codec_ok:
            criteria_met += 1
            feedback_parts.append(f"✅ Valid video codec ({codec})")
        elif codec:
            # Some codec detected, partial credit
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Unexpected codec: {codec}")
        else:
            feedback_parts.append("❌ No video codec detected")
        
        # Criterion 5: Duration check
        duration = data.get('duration', 0)
        
        if duration >= min_duration_sec:
            criteria_met += 1
            feedback_parts.append(f"✅ Sufficient duration ({duration:.1f}s)")
        elif duration > 0:
            # Some duration, partial credit
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Recording too short: {duration:.1f}s (expected > {min_duration_sec}s)")
        else:
            feedback_parts.append("❌ Duration not detected or zero")
        
        # Additional info: resolution
        width = data.get('width', 0)
        height = data.get('height', 0)
        if width > 0 and height > 0:
            feedback_parts.append(f"📐 Resolution: {width}x{height}")
            
            # Bonus: penalize if resolution is suspiciously low
            if width < 320 or height < 240:
                criteria_met -= 0.25  # Small penalty
                feedback_parts.append("⚠️ Resolution is unusually low")
        
    finally:
        cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    score = max(0, min(100, score))  # Clamp to 0-100
    passed = score >= 70
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Add summary message
    if passed:
        if score >= 95:
            summary = "✅ Excellent recording quality!"
        elif score >= 85:
            summary = "✅ Good recording with minor issues"
        else:
            summary = "✅ Recording acceptable (passing)"
    else:
        if score >= 50:
            summary = "⚠️ Partial success but not passing"
        else:
            summary = "❌ Recording failed or severely flawed"
    
    feedback = f"{summary} | {feedback}"
    
    logger.info(f"Verification result: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }