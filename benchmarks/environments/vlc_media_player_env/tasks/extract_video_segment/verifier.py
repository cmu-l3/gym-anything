#!/usr/bin/env python3
"""
Verifier for Extract Video Segment task

This verifier checks:
1. Output file exists with VLC recording naming pattern
2. File was created during task execution window
3. File size is appropriate for a 30-second segment
4. Duration is approximately 30 seconds (±3 seconds tolerance)
5. Video format is valid and readable
"""

import sys
import os
import logging
import tempfile
import time

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_video_segment(traj, env_info, task_info):
    """
    Verify video segment extraction task completion.
    
    Checks:
    1. Output file exists and is parseable
    2. File created during task window
    3. File size appropriate (not empty, not entire source)
    4. Duration is correct (~30 seconds ±3 seconds)
    5. Valid video format with proper codec
    
    Returns:
        dict with 'passed' (bool), 'score' (float 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    # Expected parameters
    EXPECTED_DURATION = 30.0  # seconds
    DURATION_TOLERANCE = 3.0  # ±3 seconds
    MIN_DURATION = EXPECTED_DURATION - DURATION_TOLERANCE  # 27s
    MAX_DURATION = EXPECTED_DURATION + DURATION_TOLERANCE  # 33s
    
    MIN_FILE_SIZE_KB = 500  # 0.5 MB minimum
    MAX_FILE_SIZE_KB = 50 * 1024  # 50 MB maximum (source is ~100MB for 10 min)
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Get task start time from completion marker
    task_start_time = None
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_segment_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            for line in f:
                if line.startswith("Task start:"):
                    # Try to extract timestamp
                    try:
                        time_part = line.split("Task start:")[1].strip()
                        # If it's a unix timestamp
                        if time_part.isdigit():
                            task_start_time = int(time_part)
                    except:
                        pass
        
        os.unlink(temp_marker.name)
    except Exception as e:
        logger.warning(f"Could not read completion marker: {e}")
        # Use a fallback - 5 minutes ago
        task_start_time = int(time.time()) - 300
    
    if task_start_time is None:
        task_start_time = int(time.time()) - 300
    
    logger.info(f"Task start time: {task_start_time}")
    
    # Criterion 1: Output file exists
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_extracted_segment.mp4",
        file_type='video'
    )
    
    if not success:
        feedback_parts.append("❌ No VLC recording found in Videos directory")
        return {
            'passed': False,
            'score': 0,
            'feedback': ' | '.join(feedback_parts) + f" ({error})"
        }
    
    criteria_met += 1
    feedback_parts.append("✅ Output file exists")
    
    video_data = file_info.get('data', {})
    filepath = file_info.get('filepath', '')
    
    # Criterion 2: File created during task window
    # Check file modification time
    try:
        file_stat = os.stat(filepath)
        file_mtime = int(file_stat.st_mtime)
        
        if file_mtime >= task_start_time:
            criteria_met += 1
            feedback_parts.append("✅ File created during task execution")
        else:
            feedback_parts.append(f"❌ File timestamp predates task start")
    except Exception as e:
        logger.warning(f"Could not check file timestamp: {e}")
        feedback_parts.append("⚠️  Could not verify file timestamp")
    
    # Criterion 3: File size appropriate
    try:
        file_size_bytes = os.path.getsize(filepath)
        file_size_kb = file_size_bytes / 1024
        
        if MIN_FILE_SIZE_KB < file_size_kb < MAX_FILE_SIZE_KB:
            criteria_met += 1
            feedback_parts.append(f"✅ File size appropriate: {file_size_kb:.1f} KB")
        else:
            if file_size_kb <= MIN_FILE_SIZE_KB:
                feedback_parts.append(f"❌ File too small: {file_size_kb:.1f} KB (min: {MIN_FILE_SIZE_KB} KB)")
            else:
                feedback_parts.append(f"❌ File too large: {file_size_kb:.1f} KB (max: {MAX_FILE_SIZE_KB} KB)")
    except Exception as e:
        logger.error(f"Error checking file size: {e}")
        feedback_parts.append("❌ Could not verify file size")
    
    # Criterion 4: Duration correct (PRIMARY CHECK)
    if 'error' in video_data:
        feedback_parts.append(f"❌ Cannot analyze video: {video_data['error']}")
    elif 'duration' not in video_data:
        feedback_parts.append("❌ Cannot determine video duration")
    else:
        duration = video_data['duration']
        
        if MIN_DURATION <= duration <= MAX_DURATION:
            criteria_met += 1
            diff = abs(duration - EXPECTED_DURATION)
            feedback_parts.append(
                f"✅ Duration correct: {duration:.1f}s "
                f"(target: {EXPECTED_DURATION}s ±{DURATION_TOLERANCE}s)"
            )
        else:
            if duration < MIN_DURATION:
                feedback_parts.append(
                    f"❌ Duration too short: {duration:.1f}s "
                    f"(expected {MIN_DURATION:.1f}-{MAX_DURATION:.1f}s)"
                )
            else:
                feedback_parts.append(
                    f"❌ Duration too long: {duration:.1f}s "
                    f"(expected {MIN_DURATION:.1f}-{MAX_DURATION:.1f}s)"
                )
    
    # Criterion 5: Valid video format
    if 'error' in video_data:
        feedback_parts.append("❌ Invalid video file")
    elif video_data.get('codec') and video_data.get('width', 0) > 0:
        criteria_met += 1
        resolution = video_data.get('resolution', 'unknown')
        codec = video_data.get('codec', 'unknown')
        feedback_parts.append(f"✅ Valid video format: {codec} {resolution}")
    else:
        feedback_parts.append("❌ Video format validation failed")
    
    # Cleanup
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate score
    score = (criteria_met / total_criteria) * 100
    passed = score >= 75.0
    
    # Build final feedback
    feedback_parts.append(f"\n📊 Score: {score:.0f}% ({criteria_met}/{total_criteria} criteria met)")
    feedback_parts.append(f"{'✅ PASS' if passed else '❌ FAIL'} (threshold: 75%)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ' | '.join(feedback_parts)
    }