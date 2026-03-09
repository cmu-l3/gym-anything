#!/usr/bin/env python3
"""
Verifier for Create Reaction GIF task

This verifier checks:
1. GIF file exists and is valid
2. GIF duration is approximately 3.5 seconds (±0.3s)
3. File size is ≤ 8 MB
4. Resolution is reasonable (width ≤ 500px with tolerance)
5. GIF is animated (has multiple frames)
6. Frame rate is reasonable (8-20 fps range)
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_reaction_gif(traj, env_info, task_info):
    """
    Verify create reaction GIF task completion.
    
    Checks:
    1. GIF file exists and is valid format
    2. Duration is approximately 3.5 seconds (±0.3s tolerance)
    3. File size is ≤ 8 MB
    4. Resolution is appropriate (width ≤ 500px)
    5. GIF is animated (has 10+ frames)
    6. Frame rate is reasonable (8-20 fps)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Copy and verify GIF file
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_reaction.gif",
        file_type='video'  # ffprobe can handle GIFs
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"GIF file not found or inaccessible: {error}"
        }
    
    # Criterion 1: File exists and is valid
    criteria_met += 1
    feedback_parts.append("✅ GIF file exists")
    
    gif_data = file_info.get('data', {})
    filepath = file_info.get('filepath', '')
    
    # Check if it's actually a GIF
    if not filepath.lower().endswith('.gif'):
        feedback_parts.append("⚠️ File may not be a GIF format")
    
    # Get file size
    try:
        file_size_bytes = os.path.getsize(filepath)
        file_size_mb = file_size_bytes / (1024 * 1024)
    except Exception as e:
        logger.error(f"Error getting file size: {e}")
        file_size_mb = 0
    
    # Criterion 2: Duration check (3.5s ±0.3s = 3.2s to 3.8s)
    duration = gif_data.get('duration', 0)
    if duration > 0:
        if 3.2 <= duration <= 3.8:
            criteria_met += 1
            feedback_parts.append(f"✅ Duration correct: {duration:.2f}s (target: 3.5s)")
        elif 3.0 <= duration <= 4.0:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Duration close: {duration:.2f}s (target: 3.5s ±0.3s)")
        else:
            feedback_parts.append(f"❌ Duration incorrect: {duration:.2f}s (expected: 3.2-3.8s)")
    else:
        feedback_parts.append("❌ Duration not detected")
    
    # Criterion 3: File size check (≤ 8 MB)
    if file_size_mb > 0:
        if file_size_mb <= 8.0:
            criteria_met += 1
            feedback_parts.append(f"✅ File size OK: {file_size_mb:.2f} MB (max: 8 MB)")
        elif file_size_mb <= 10.0:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ File size slightly over: {file_size_mb:.2f} MB (target: ≤8 MB)")
        else:
            feedback_parts.append(f"❌ File size too large: {file_size_mb:.2f} MB (max: 8 MB)")
    else:
        feedback_parts.append("⚠️ File size unknown")
    
    # Criterion 4: Resolution check (width ≤ 500px)
    width = gif_data.get('width', 0)
    height = gif_data.get('height', 0)
    
    if width > 0:
        if width <= 500:
            criteria_met += 1
            feedback_parts.append(f"✅ Resolution appropriate: {width}x{height} (max width: 500px)")
        elif width <= 600:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Resolution slightly large: {width}x{height} (target: ≤480px)")
        else:
            feedback_parts.append(f"❌ Resolution too large: {width}x{height} (max width: 500px)")
    else:
        feedback_parts.append("⚠️ Resolution not detected")
    
    # Criterion 5: Check if animated (frame count)
    # For GIFs, we need to check if there are multiple frames
    # ffprobe may not always report nb_frames for GIFs, so we use duration and fps
    fps = gif_data.get('fps', 0)
    
    if fps > 0 and duration > 0:
        frame_count = int(fps * duration)
    else:
        frame_count = 0
    
    if frame_count >= 10:
        criteria_met += 1
        feedback_parts.append(f"✅ Animated: {frame_count} frames (~{fps:.1f} fps)")
    elif frame_count > 0:
        criteria_met += 0.5
        feedback_parts.append(f"⚠️ Few frames: {frame_count} frames (may be choppy)")
    else:
        # Try alternative method: check if format indicates multiple images
        format_name = gif_data.get('format', '')
        if 'gif' in format_name.lower():
            criteria_met += 0.5
            feedback_parts.append("⚠️ GIF format detected (assuming animated)")
        else:
            feedback_parts.append("❌ Animation not confirmed")
    
    # Criterion 6: Frame rate check (8-20 fps is reasonable)
    if fps > 0:
        if 8 <= fps <= 20:
            criteria_met += 1
            feedback_parts.append(f"✅ Frame rate optimal: {fps:.1f} fps")
        elif 5 <= fps <= 30:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Frame rate acceptable: {fps:.1f} fps (optimal: 10-15)")
        else:
            feedback_parts.append(f"⚠️ Frame rate unusual: {fps:.1f} fps")
    else:
        feedback_parts.append("⚠️ Frame rate not detected")
    
    # Clean up temporary files
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker (bonus, doesn't affect main criteria)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_gif_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        if "GIF found: true" in content:
            feedback_parts.append("✅ Task completed successfully")
        os.unlink(temp_marker.name)
    except Exception as e:
        logger.debug(f"Completion marker check: {e}")
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    # Each criterion is worth 1 point, total 6 points
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75  # Need 4.5/6 criteria to pass
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: {criteria_met}/{total_criteria} criteria met, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }