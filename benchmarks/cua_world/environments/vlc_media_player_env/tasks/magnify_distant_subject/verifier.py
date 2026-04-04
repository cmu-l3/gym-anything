#!/usr/bin/env python3
"""
Verifier for Magnify Distant Subject task

Verifies that the agent successfully:
1. Created a magnified/cropped output video
2. The output has different resolution (indicating crop was applied)
3. The output video is valid and playable
4. The crop dimensions are reasonable for the upper-right quadrant
"""

import sys
import os
import logging

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    copy_and_parse_media,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_magnify_distant_subject(traj, env_info, task_info):
    """
    Verify magnify distant subject task completion.
    
    Checks:
    1. Output video file exists and is parseable
    2. Video resolution changed from original (1920x1080)
    3. Video has reasonable duration (~30 seconds)
    4. Output dimensions suggest a cropped region (not full frame)
    5. Video is valid and playable
    
    Args:
        traj: Trajectory information (unused in this verifier)
        env_info: Environment info dict with 'copy_from_env' function
        task_info: Task information (unused in this verifier)
        
    Returns:
        dict with keys: 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    output_path = "/tmp/vlc_magnified_video.mp4"
    
    # Copy and parse the magnified video
    success, data, error, temp_dir = copy_and_parse_media(
        output_path, 
        copy_from_env,
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Magnified video not found or failed to copy: {error}"
        }
    
    # Criterion 1: File exists and is parseable
    criteria_met += 1
    feedback_parts.append("✅ Output video file exists")
    
    # Check for errors in parsed data
    if 'error' in data:
        cleanup_verification_temp(temp_dir)
        return {
            "passed": False, 
            "score": 20, 
            "feedback": f"❌ Output video is corrupted or invalid: {data['error']}"
        }
    
    # Extract video properties
    width = data.get('width', 0)
    height = data.get('height', 0)
    duration = data.get('duration', 0)
    codec = data.get('codec', '')
    size_bytes = data.get('size_bytes', 0)
    size_mb = size_bytes / (1024 * 1024)
    
    logger.info(f"Output video properties: {width}x{height}, {duration:.1f}s, {codec}, {size_mb:.2f}MB")
    
    # Criterion 2: Resolution changed from original (1920x1080)
    if width == 1920 and height == 1080:
        feedback_parts.append("❌ Resolution unchanged (1920x1080) - no crop/zoom applied")
    elif width > 0 and height > 0:
        criteria_met += 1
        feedback_parts.append(f"✅ Resolution changed to {width}x{height} (cropped)")
    else:
        feedback_parts.append(f"❌ Invalid resolution: {width}x{height}")
    
    # Criterion 3: Duration is reasonable (~30 seconds, allow ±5s tolerance)
    if duration < 20:
        feedback_parts.append(f"⚠️ Output video too short ({duration:.1f}s, expected ~30s)")
    elif duration > 35:
        feedback_parts.append(f"⚠️ Output video too long ({duration:.1f}s, expected ~30s)")
    else:
        criteria_met += 1
        feedback_parts.append(f"✅ Duration valid ({duration:.1f}s)")
    
    # Criterion 4: Output dimensions suggest reasonable crop
    # Expected: cropped region roughly 300-800 pixels wide/tall
    # (upper-right quadrant crop would be approximately 500x400 to 700x600)
    if width < 200 or width > 1000 or height < 150 or height > 900:
        # Dimensions are suspicious (too small or too large for expected crop)
        feedback_parts.append(
            f"⚠️ Crop dimensions unusual ({width}x{height}) - expected region crop ~400-700px"
        )
        # Partial credit if dimensions at least changed
        if width != 1920 or height != 1080:
            criteria_met += 0.5
    else:
        criteria_met += 1
        feedback_parts.append(f"✅ Crop dimensions reasonable ({width}x{height})")
    
    # Criterion 5: Video is valid (has codec, non-zero size)
    if size_bytes < 50 * 1024:  # Less than 50 KB
        feedback_parts.append(f"❌ Output file too small ({size_mb:.2f}MB) - likely corrupted")
    elif not codec:
        feedback_parts.append("⚠️ Video codec not detected")
    else:
        criteria_met += 1
        feedback_parts.append(f"✅ Video valid ({codec}, {size_mb:.2f}MB)")
    
    # Cleanup temp directory
    cleanup_verification_temp(temp_dir)
    
    # Calculate final score (percentage)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need at least 70% to pass
    
    # Build feedback message
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        summary = f"✅ Task completed successfully! Score: {score}/100"
    else:
        summary = f"❌ Task incomplete. Score: {score}/100 (need 70+ to pass)"
    
    feedback = f"{summary} | {feedback}"
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }