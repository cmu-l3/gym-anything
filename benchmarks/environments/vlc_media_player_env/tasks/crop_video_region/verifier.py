#!/usr/bin/env python3
"""
Verifier for Crop Video Region task
"""

import sys
import os
import logging

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    verify_video_duration,
    verify_video_resolution,
    copy_and_parse_media,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_crop_video_region(traj, env_info, task_info):
    """
    Verify crop video region task completion.
    
    Checks:
    1. Output file exists and is valid
    2. Resolution is correct (1920x800, ±10 pixels tolerance)
    3. Duration is preserved (~10 seconds, ±2 seconds tolerance)
    4. File is a valid video (has codec, reasonable size)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        Dict with passed (bool), score (int), feedback (str), and metadata (dict)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "metadata": {}
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    metadata = {}
    temp_dir = None
    
    try:
        # Expected output path in container
        output_path = "/tmp/vlc_cropped_output.mp4"
        
        # Copy and parse the output video
        success, video_data, error, temp_dir = copy_and_parse_media(
            output_path,
            copy_from_env,
            file_type='video'
        )
        
        if not success:
            feedback_parts.append(f"❌ Output file not found or invalid: {error}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts),
                "metadata": {"error": error}
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Output file exists and is parseable")
        
        # Extract video properties
        actual_width = video_data.get('width', 0)
        actual_height = video_data.get('height', 0)
        actual_duration = video_data.get('duration', 0)
        codec = video_data.get('codec', 'unknown')
        size_bytes = video_data.get('size_bytes', 0)
        size_mb = size_bytes / (1024 * 1024)
        
        # Store in metadata
        metadata['output_resolution'] = f"{actual_width}x{actual_height}"
        metadata['output_duration'] = round(actual_duration, 2)
        metadata['output_codec'] = codec
        metadata['output_size_mb'] = round(size_mb, 2)
        
        # Expected values
        expected_width = 1920
        expected_height = 800
        expected_duration = 10.0
        resolution_tolerance = 10
        duration_tolerance = 2.0
        
        metadata['expected_resolution'] = f"{expected_width}x{expected_height}"
        metadata['expected_duration'] = expected_duration
        
        # Criterion 2: Check resolution (most important - double weight)
        width_ok = abs(actual_width - expected_width) <= resolution_tolerance
        height_ok = abs(actual_height - expected_height) <= resolution_tolerance
        
        if width_ok and height_ok:
            criteria_met += 1.5  # Higher weight for correct resolution
            feedback_parts.append(
                f"✅ Resolution correct: {actual_width}x{actual_height} "
                f"(expected {expected_width}x{expected_height})"
            )
        else:
            feedback_parts.append(
                f"❌ Resolution mismatch: got {actual_width}x{actual_height}, "
                f"expected {expected_width}x{expected_height} (±{resolution_tolerance}px)"
            )
            metadata['resolution_error'] = {
                'width_diff': actual_width - expected_width,
                'height_diff': actual_height - expected_height
            }
        
        # Criterion 3: Check duration
        duration_ok = abs(actual_duration - expected_duration) <= duration_tolerance
        
        if duration_ok:
            criteria_met += 1
            feedback_parts.append(
                f"✅ Duration preserved: {actual_duration:.1f}s "
                f"(expected ~{expected_duration}s)"
            )
        else:
            feedback_parts.append(
                f"⚠️  Duration mismatch: {actual_duration:.1f}s "
                f"(expected ~{expected_duration}s ±{duration_tolerance}s)"
            )
            metadata['duration_error'] = actual_duration - expected_duration
        
        # Criterion 4: Check video is valid
        valid_video = True
        
        # Check codec
        if not codec or codec == 'unknown':
            feedback_parts.append("⚠️  Codec unknown or not detected")
            valid_video = False
        else:
            feedback_parts.append(f"ℹ️  Codec: {codec}")
        
        # Check file size (should be at least 100 KB for a valid 10-second video)
        min_size_kb = 100
        if size_mb * 1024 < min_size_kb:
            feedback_parts.append(
                f"❌ Output file too small: {size_mb * 1024:.1f} KB "
                f"(minimum: {min_size_kb} KB)"
            )
            valid_video = False
        else:
            feedback_parts.append(f"✅ File size reasonable: {size_mb:.2f} MB")
        
        if valid_video:
            criteria_met += 0.5  # Partial credit for valid video
        
        # Check for error in video data
        if 'error' in video_data:
            feedback_parts.append(f"⚠️  Video parsing warning: {video_data['error']}")
            metadata['parse_warning'] = video_data['error']
        
        # Final assessment
        if criteria_met >= 3:
            feedback_parts.append("")
            feedback_parts.append("🎉 Task completed successfully!")
            feedback_parts.append(
                f"Video cropped from 1920x1080 to {actual_width}x{actual_height}, "
                f"removing letterbox bars with hardcoded overlays."
            )
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "metadata": {"exception": str(e)}
        }
    
    finally:
        # Cleanup temporary files
        if temp_dir:
            cleanup_verification_environment(temp_dir)
    
    # Calculate score (criteria_met can be fractional)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Add score to feedback
    feedback_parts.insert(0, f"Score: {score}/100 (threshold: 75)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "metadata": metadata
    }
