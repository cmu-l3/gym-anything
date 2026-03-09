#!/usr/bin/env python3
"""
Verifier for mirror_dance_video task

Checks that video was rotated 90° clockwise and saved.
We verify rotation by checking resolution change from portrait to landscape.
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
    verify_video_duration,
    copy_and_parse_media,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_transformation_applied(video_info: dict) -> dict:
    """
    Verify video transformation by analyzing resolution.
    
    Original: 720x1280 portrait
    Expected after 90° clockwise rotation: ~1280x720 landscape
    
    Args:
        video_info: Video info dict from get_video_info
        
    Returns:
        Dict with success, actual dimensions, and detailed checks
    """
    width = video_info.get('width', 0)
    height = video_info.get('height', 0)
    
    # Expected dimensions after 90° clockwise rotation of 720x1280
    # Allow some tolerance for encoding (codecs may adjust dimensions slightly)
    expected_width = 1280
    expected_height = 720
    width_tolerance = 100  # Allow up to 100px difference
    height_tolerance = 100
    
    width_ok = abs(width - expected_width) <= width_tolerance
    height_ok = abs(height - expected_height) <= height_tolerance
    
    # Check if it's landscape (width > height)
    is_landscape = width > height
    
    # Check if dimensions are swapped from original
    dimensions_swapped = (
        abs(width - 1280) <= width_tolerance and 
        abs(height - 720) <= height_tolerance
    )
    
    return {
        'success': width_ok and height_ok and is_landscape,
        'width': width,
        'height': height,
        'expected_width': expected_width,
        'expected_height': expected_height,
        'width_ok': width_ok,
        'height_ok': height_ok,
        'is_landscape': is_landscape,
        'dimensions_swapped': dimensions_swapped,
        'resolution': f"{width}x{height}"
    }


def verify_mirror_dance_video(traj, env_info, task_info):
    """
    Main verification function for mirror_dance_video task.
    
    Verification strategy:
    1. Output file exists
    2. Video has valid properties (not corrupted)
    3. Duration matches original (~45s ±2s)
    4. Resolution indicates rotation was applied (portrait → landscape)
    5. File size is reasonable (not broken encoding)
    
    Note: We cannot easily verify horizontal flip without frame-by-frame analysis,
    but the resolution change is a strong indicator that transformations were applied.
    
    Args:
        traj: Trajectory data (not used in this verifier)
        env_info: Environment info including copy_from_env function
        task_info: Task info (not used in this verifier)
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    logger.info("Starting mirror_dance_video verification...")
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available for verification"
        }
    
    criteria_met = 0.0
    total_criteria = 5.0
    feedback_parts = []
    
    output_container_path = "/tmp/vlc_mirror_dance_output.mp4"
    
    # Check 1: Output file exists (20 points)
    temp_dir = tempfile.mkdtemp(prefix='vlc_mirror_verify_')
    temp_video = os.path.join(temp_dir, 'output.mp4')
    
    try:
        # Check if .missing marker exists (indicates no output was found)
        missing_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.missing')
        try:
            copy_from_env(f"{output_container_path}.missing", missing_marker.name)
            # If we get here, the missing marker exists
            os.unlink(missing_marker.name)
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Output video file not found at /home/ga/Videos/dance_demo_mirrored.mp4"
            }
        except Exception:
            # Missing marker doesn't exist, continue to check for actual file
            os.unlink(missing_marker.name)
            pass
        
        # Try to copy the output video
        try:
            copy_from_env(output_container_path, temp_video)
        except Exception as e:
            logger.error(f"Failed to copy output video: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy output video: {str(e)}"
            }
        
        # Verify file exists and is not empty
        if not os.path.exists(temp_video):
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Output video file not found"
            }
        
        file_size = os.path.getsize(temp_video)
        if file_size < 1000:  # Less than 1 KB suggests empty or broken file
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 10,
                "feedback": f"❌ Output video file is too small ({file_size} bytes) - likely corrupted"
            }
        
        feedback_parts.append("✅ Output video file exists")
        criteria_met += 1.0
        
        # Check 2: Parse video info (10 points for valid video)
        video_info = get_video_info(temp_video)
        
        if 'error' in video_info:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 20,
                "feedback": f"❌ Cannot read video properties: {video_info['error']}"
            }
        
        feedback_parts.append("✅ Video file is valid and readable")
        criteria_met += 0.5
        
        # Check 3: Video has reasonable duration (20 points)
        duration = video_info.get('duration', 0)
        expected_duration = 45.0
        duration_tolerance = 3.0  # Allow ±3 seconds
        
        if duration == 0:
            feedback_parts.append("⚠️  Duration not detected (may still be valid)")
        elif abs(duration - expected_duration) <= duration_tolerance:
            feedback_parts.append(f"✅ Duration correct: {duration:.1f}s (expected ~{expected_duration}s)")
            criteria_met += 1.0
        else:
            feedback_parts.append(f"⚠️  Duration mismatch: {duration:.1f}s (expected ~{expected_duration}s ±{duration_tolerance}s)")
            criteria_met += 0.3  # Partial credit
        
        # Check 4: File size is reasonable (10 points)
        size_kb = file_size / 1024
        min_size_kb = 50  # At least 50 KB for 45s video
        
        if size_kb < min_size_kb:
            feedback_parts.append(f"⚠️  Video file very small ({size_kb:.1f} KB) - may be corrupted")
        else:
            feedback_parts.append(f"✅ File size reasonable: {size_kb:.1f} KB")
            criteria_met += 0.5
        
        # Check 5: Resolution indicates rotation was applied (40 points - MOST IMPORTANT)
        transformation = verify_transformation_applied(video_info)
        
        if transformation['success']:
            feedback_parts.append(
                f"✅ ✅ Video ROTATED correctly: {transformation['resolution']} (landscape orientation)"
            )
            criteria_met += 2.0  # Full points for successful rotation
        elif transformation['is_landscape']:
            feedback_parts.append(
                f"✅ Video is landscape: {transformation['resolution']} (rotation likely applied)"
            )
            criteria_met += 1.5  # Partial credit if landscape but dimensions not exact
        else:
            feedback_parts.append(
                f"❌ Video NOT rotated properly: {transformation['resolution']} "
                f"(expected ~{transformation['expected_width']}x{transformation['expected_height']} landscape)"
            )
            # No points for this criterion
        
        # Check codec is reasonable (bonus)
        codec = video_info.get('codec', '').lower()
        valid_codecs = ['h264', 'hevc', 'mpeg4', 'vp9', 'vp8', 'h265']
        if codec in valid_codecs:
            feedback_parts.append(f"✅ Valid video codec: {codec}")
        else:
            feedback_parts.append(f"⚠️  Codec: {codec or 'unknown'}")
        
        # Calculate final score
        score = (criteria_met / total_criteria) * 100
        passed = score >= 70  # Need 70% to pass
        
        # Build detailed feedback
        feedback_message = "\n".join(feedback_parts)
        
        # Add result summary
        if passed:
            feedback_message += f"\n\n🎉 SUCCESS! Video transformed correctly (Score: {score:.1f}%)"
            feedback_message += "\n✅ The video has been rotated to landscape orientation."
            if transformation.get('dimensions_swapped'):
                feedback_message += "\n✅ Portrait → Landscape transformation confirmed!"
        else:
            feedback_message += f"\n\n❌ TASK INCOMPLETE (Score: {score:.1f}%)"
            if not transformation['success']:
                feedback_message += "\n❌ Main issue: Video rotation not detected."
                feedback_message += "\n   → Ensure you applied ROTATION (90° clockwise) in Effects and Filters"
                feedback_message += "\n   → AND converted the video with effects applied"
            else:
                feedback_message += "\n   → Ensure all transformations are applied during conversion"
        
        # Note about horizontal flip
        feedback_message += "\n\nℹ️  Note: Horizontal flip verification requires visual inspection."
        feedback_message += "\n   Resolution check confirms rotation was applied."
        
        logger.info(f"Verification complete: passed={passed}, score={score:.1f}%")
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback_message
        }
    
    finally:
        # Cleanup temporary files
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                logger.debug(f"Cleaned up temp directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")
