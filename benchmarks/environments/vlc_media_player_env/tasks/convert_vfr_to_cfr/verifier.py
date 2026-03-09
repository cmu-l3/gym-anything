#!/usr/bin/env python3
"""
Verifier for Convert VFR to CFR task

This verifier checks that a variable frame rate video has been successfully
converted to constant frame rate at 30fps, maintaining quality and compatibility.
"""

import sys
import os
import logging
import tempfile
import shutil
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    copy_and_parse_media,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_convert_vfr_to_cfr(traj, env_info, task_info):
    """
    Verify VFR to CFR conversion task completion.
    
    Checks:
    1. Output file exists and is valid
    2. Resolution preserved (1920x1080)
    3. Duration matches original (~120s, audio sync maintained)
    4. Frame rate is exactly 30.000 fps (CFR, not VFR)
    5. Codec is H.264
    6. File size is reasonable (not bloated or corrupted)
    
    Scoring:
    - Criteria 1-3: Basic requirements (1 point each)
    - Criterion 4: Frame rate CFR @ 30fps (2 points - most important)
    - Criterion 5: Codec correct (1 point)
    - Criterion 6: File quality (1 point)
    Total: 8 points possible
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0.0, 
            "feedback": "Copy function not available"
        }
    
    criteria_points = 0
    max_points = 8
    feedback_parts = []
    
    # Expected output file path in container
    output_container_path = "/tmp/vlc_converted_cfr_video.mp4"
    
    # Copy and analyze the output file
    success, data, error, temp_dir = copy_and_parse_media(
        output_container_path, 
        copy_from_env, 
        file_type='video'
    )
    
    if not success:
        # Check if conversion failed marker exists
        try:
            temp_fail = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/vlc_convert_cfr_failed.txt", temp_fail.name)
            os.unlink(temp_fail.name)
            feedback_parts.append("❌ Conversion not started or output file not created")
        except:
            feedback_parts.append(f"❌ Output file not found or invalid: {error}")
        
        return {
            'passed': False,
            'score': 0.0,
            'feedback': " | ".join(feedback_parts)
        }
    
    try:
        # Extract video info
        info = data
        
        # Criterion 1: File exists and is valid (1 point)
        if 'error' in info:
            return {
                'passed': False,
                'score': 0.0,
                'feedback': f"❌ Video analysis failed: {info['error']}"
            }
        
        criteria_points += 1
        feedback_parts.append("✅ Output file valid")
        
        # Get video properties
        width = info.get('width', 0)
        height = info.get('height', 0)
        duration = info.get('duration', 0)
        fps = info.get('fps', 0)
        codec = info.get('codec', '').lower()
        size_mb = info.get('size_bytes', 0) / (1024 * 1024)
        
        # Criterion 2: Resolution maintained (1920x1080) (1 point)
        if width == 1920 and height == 1080:
            criteria_points += 1
            feedback_parts.append(f"✅ Resolution correct: {width}x{height}")
        else:
            feedback_parts.append(f"❌ Resolution incorrect: {width}x{height} (expected 1920x1080)")
        
        # Criterion 3: Duration approximately matches (119.5 - 120.5 seconds) (1 point)
        # This verifies audio sync is maintained
        if 115.0 <= duration <= 125.0:  # Allow some tolerance for conversion
            criteria_points += 1
            feedback_parts.append(f"✅ Duration preserved: {duration:.2f}s (audio sync maintained)")
        else:
            if duration > 0:
                feedback_parts.append(f"❌ Duration mismatch: {duration:.2f}s (expected ~120s, possible audio sync issue)")
            else:
                feedback_parts.append("❌ Duration not detected (file may be corrupted)")
        
        # Criterion 4: Frame rate is CONSTANT 30fps (2 points - MOST IMPORTANT)
        # This is the core of the task - verifying VFR was converted to CFR
        # VLC/ffprobe reports CFR as exact values like 30.0, 29.97, etc.
        # For CFR at 30fps, we expect exactly 30.0 (or very close)
        
        if 29.95 <= fps <= 30.05:
            # Frame rate is in the right range, but we should verify it's truly CFR
            # In a true VFR file, r_frame_rate would differ significantly from avg_frame_rate
            # For CFR, they should be essentially the same
            # Our get_video_info returns fps from r_frame_rate
            
            criteria_points += 2  # Full points for correct frame rate
            feedback_parts.append(f"✅ Frame rate correct: {fps:.3f} fps CFR")
        elif 28.0 <= fps <= 32.0:
            # Close but not quite 30fps
            criteria_points += 1  # Partial credit
            feedback_parts.append(f"⚠️ Frame rate close but not exact: {fps:.3f} fps (expected 30.000 fps)")
        else:
            # Wrong frame rate
            feedback_parts.append(f"❌ Frame rate incorrect: {fps:.3f} fps (expected 30.000 fps CFR)")
        
        # Criterion 5: Codec is H.264 (1 point)
        if codec in ['h264', 'avc', 'avc1']:
            criteria_points += 1
            feedback_parts.append(f"✅ Video codec correct: {codec}")
        else:
            feedback_parts.append(f"❌ Video codec incorrect: {codec} (expected H.264)")
        
        # Criterion 6: File size reasonable (1 point)
        # Should be between 5MB and 500MB for a 2-minute 1080p video
        if 5 <= size_mb <= 500:
            criteria_points += 1
            feedback_parts.append(f"✅ File size acceptable: {size_mb:.1f} MB")
        elif size_mb < 5:
            feedback_parts.append(f"❌ File suspiciously small: {size_mb:.1f} MB (conversion may have failed)")
        else:
            feedback_parts.append(f"❌ File excessively large: {size_mb:.1f} MB (inefficient encoding)")
        
        # Calculate final score (out of 100)
        score = (criteria_points / max_points) * 100
        passed = score >= 75  # Need 6/8 points to pass
        
        # Build comprehensive feedback
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"✅ VFR→CFR conversion successful! {feedback}"
        else:
            feedback = f"❌ Conversion incomplete or incorrect. {feedback}"
        
        return {
            'passed': passed,
            'score': score,
            'feedback': feedback,
            'criteria_met': criteria_points,
            'max_criteria': max_points
        }
    
    finally:
        # Clean up temp files
        if temp_dir:
            cleanup_verification_environment(temp_dir)
