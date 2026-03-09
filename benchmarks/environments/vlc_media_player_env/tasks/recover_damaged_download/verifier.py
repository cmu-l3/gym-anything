#!/usr/bin/env python3
"""
Verifier for Recover Damaged Download task

Validates that agent successfully:
1. Extracted playable portion from corrupted video
2. Saved it as a valid, clean file
3. Recovered appropriate duration (partial, not full or empty)
4. Output is fully playable without errors
"""

import sys
import os
import logging
import tempfile
import json
import subprocess
import shutil
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def verify_file_is_playable(filepath: str) -> tuple:
    """
    Verify video file is actually playable without corruption.
    
    Returns:
        (is_playable: bool, message: str)
    """
    try:
        # Try to decode first 10 seconds to check for corruption
        cmd = [
            'ffmpeg',
            '-v', 'error',
            '-i', filepath,
            '-t', '10',
            '-f', 'null',
            '-'
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0 and len(result.stderr) < 100:
            return True, "File is playable without errors"
        else:
            error_snippet = result.stderr[:200] if result.stderr else "unknown error"
            return False, f"Playback errors detected: {error_snippet}"
            
    except subprocess.TimeoutExpired:
        return False, "Playback test timeout - file may be severely corrupted"
    except Exception as e:
        return False, f"Playback test failed: {str(e)}"


def verify_recover_damaged_download(traj, env_info, task_info):
    """
    Main verification function for damaged file recovery task.
    
    Checks:
    1. Recovered file exists and can be copied
    2. File has valid video properties (codec, resolution)
    3. Duration is appropriate (6-9 minutes for our 10-min test, proving partial recovery)
    4. File size is reasonable (not empty, not suspiciously large)
    5. File is fully playable without errors
    
    Scoring:
    - Each criterion contributes to total score
    - Must achieve 75% to pass
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify"
        }
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Criterion 1: Check if recovered file exists and can be retrieved
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_recovered_video.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Recovered file not found or empty: {error}"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Recovered file exists")
    
    # Get video information
    video_data = file_info.get('data', {})
    
    if 'error' in video_data:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 20,
            "feedback": f"❌ Recovered file is corrupted or invalid: {video_data['error']}"
        }
    
    # Criterion 2: Check video has valid properties (codec, resolution)
    codec = video_data.get('codec', '')
    width = video_data.get('width', 0)
    height = video_data.get('height', 0)
    
    if codec and width >= 640 and height >= 480:
        criteria_met += 1
        feedback_parts.append(f"✅ Valid video format ({codec}, {width}x{height})")
    else:
        feedback_parts.append(f"❌ Invalid video properties (codec: {codec}, resolution: {width}x{height})")
    
    # Criterion 3: Check duration is appropriate (partial recovery)
    duration = video_data.get('duration', 0)
    duration_minutes = duration / 60.0
    
    # Expected: 6-9 minutes (60-90% of 10-minute original)
    # This proves it's partial recovery, not full file or empty
    MIN_DURATION = 360  # 6 minutes in seconds
    MAX_DURATION = 540  # 9 minutes in seconds
    
    if MIN_DURATION <= duration <= MAX_DURATION:
        criteria_met += 1
        feedback_parts.append(f"✅ Appropriate duration ({duration_minutes:.1f} min - partial recovery confirmed)")
    elif duration < MIN_DURATION:
        feedback_parts.append(f"❌ Duration too short ({duration_minutes:.1f} min < 6 min required) - insufficient recovery")
    else:
        feedback_parts.append(f"❌ Duration too long ({duration_minutes:.1f} min > 9 min max) - may contain corrupted data")
    
    # Criterion 4: Check file size is reasonable
    size_mb = video_data.get('size_bytes', 0) / (1024 * 1024)
    
    # For 6-9 minutes of 720p H.264 video at moderate quality, expect 30-150 MB
    MIN_SIZE_MB = 20  # Minimum reasonable size
    MAX_SIZE_MB = 200  # Maximum reasonable size
    
    if MIN_SIZE_MB <= size_mb <= MAX_SIZE_MB:
        criteria_met += 1
        feedback_parts.append(f"✅ Reasonable file size ({size_mb:.1f} MB)")
    elif size_mb < MIN_SIZE_MB:
        feedback_parts.append(f"❌ File too small ({size_mb:.1f} MB) - may be corrupted or improperly encoded")
    else:
        feedback_parts.append(f"⚠️ File larger than expected ({size_mb:.1f} MB) but acceptable")
        criteria_met += 0.5  # Partial credit
    
    # Criterion 5: Verify file is actually playable (crucial for recovery task)
    filepath = file_info.get('filepath')
    is_playable, play_message = verify_file_is_playable(filepath)
    
    if is_playable:
        criteria_met += 1
        feedback_parts.append(f"✅ File fully playable - {play_message}")
    else:
        feedback_parts.append(f"❌ File playback issues - {play_message}")
    
    # Cleanup temporary files
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback message
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        summary = f"✅ SUCCESS: Recovered {duration_minutes:.1f} min of playable video ({size_mb:.1f} MB)"
    else:
        summary = f"❌ INCOMPLETE: Recovery did not meet all criteria ({criteria_met}/{total_criteria})"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | {feedback}"
    }
