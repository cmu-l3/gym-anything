#!/usr/bin/env python3
"""
Verifier for Fix Portrait Video task

This verifier checks if the agent successfully converted a portrait-mode video (9:16)
to landscape format (16:9) using VLC's conversion and geometric transformation features.
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


def verify_fix_portrait_video(traj, env_info, task_info):
    """
    Verify portrait video conversion task completion.
    
    Verification Criteria (6 total, need 5+ to pass):
    1. Output file exists and is non-empty
    2. File size is reasonable (1MB - 100MB)
    3. Aspect ratio is 16:9 (width/height ≈ 1.778, tolerance ±0.05)
    4. Video is in landscape orientation (width > height)
    5. Duration is preserved (within ±10% of original ~30 seconds)
    6. Video is playable with valid codec
    
    Pass threshold: 83% (5/6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Original video properties
    original_duration = 30.0  # seconds
    target_aspect_ratio = 16.0 / 9.0  # 1.7778
    
    # Copy and analyze converted video
    output_path = "/tmp/vlc_portrait_corrected.mp4"
    
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        output_path,
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Output file not found or unreadable: {error}"
        }
    
    video_data = file_info.get('data', {})
    temp_dir = file_info.get('temp_dir')
    
    try:
        # Criterion 1: File exists (already passed if we got here)
        criteria_met += 1
        feedback_parts.append("✅ Output file exists")
        
        # Criterion 2: Reasonable file size (1MB - 100MB)
        size_bytes = video_data.get('size_bytes', 0)
        size_mb = size_bytes / (1024 * 1024)
        
        if 1.0 <= size_mb <= 100.0:
            criteria_met += 1
            feedback_parts.append(f"✅ File size reasonable: {size_mb:.1f} MB")
        else:
            feedback_parts.append(f"❌ File size suspicious: {size_mb:.1f} MB (expected 1-100 MB)")
        
        # Get video dimensions
        width = video_data.get('width', 0)
        height = video_data.get('height', 0)
        
        if width == 0 or height == 0:
            feedback_parts.append("❌ Could not determine video resolution")
            return {
                "passed": False,
                "score": int((criteria_met / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 3: Correct aspect ratio (16:9 ≈ 1.778)
        actual_aspect_ratio = width / height
        aspect_ratio_diff = abs(actual_aspect_ratio - target_aspect_ratio)
        
        # Tolerance: ±0.05 (allows 1.73 to 1.83)
        if 1.73 <= actual_aspect_ratio <= 1.83:
            criteria_met += 1
            feedback_parts.append(
                f"✅ Aspect ratio correct: {actual_aspect_ratio:.3f} "
                f"(target: {target_aspect_ratio:.3f}, diff: {aspect_ratio_diff:.3f})"
            )
        else:
            feedback_parts.append(
                f"❌ Aspect ratio wrong: {actual_aspect_ratio:.3f} "
                f"(expected ~{target_aspect_ratio:.3f})"
            )
        
        # Criterion 4: Landscape orientation (width > height)
        if width > height:
            criteria_met += 1
            feedback_parts.append(f"✅ Landscape orientation: {width}x{height}")
        else:
            feedback_parts.append(
                f"❌ Still portrait orientation: {width}x{height} "
                f"(width should be > height)"
            )
        
        # Criterion 5: Duration preserved (±10% of original)
        output_duration = video_data.get('duration', 0)
        min_duration = original_duration * 0.9
        max_duration = original_duration * 1.1
        
        if output_duration > 0:
            if min_duration <= output_duration <= max_duration:
                criteria_met += 1
                feedback_parts.append(
                    f"✅ Duration preserved: {output_duration:.1f}s "
                    f"(original: {original_duration}s)"
                )
            else:
                duration_diff_pct = abs(output_duration - original_duration) / original_duration * 100
                feedback_parts.append(
                    f"⚠️ Duration mismatch: {output_duration:.1f}s "
                    f"(expected ~{original_duration}s, diff: {duration_diff_pct:.0f}%)"
                )
        else:
            feedback_parts.append("❌ Duration not found or zero")
        
        # Criterion 6: Valid video codec
        codec = video_data.get('codec', '').lower()
        valid_codecs = ['h264', 'h265', 'hevc', 'vp9', 'vp8', 'mpeg4', 'xvid', 'mpeg2video']
        
        if codec in valid_codecs:
            criteria_met += 1
            feedback_parts.append(f"✅ Valid codec: {codec}")
        else:
            if codec:
                feedback_parts.append(f"⚠️ Unusual codec: {codec} (expected h264, vp9, etc.)")
            else:
                feedback_parts.append("❌ Invalid/unknown codec")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = criteria_met >= 5  # Need 5/6 to pass (83%)
        
        # Add summary
        feedback_parts.append(f"Score: {criteria_met}/{total_criteria} criteria met")
        
        feedback = " | ".join(feedback_parts)
        
        result = {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": {
                "criteria_met": criteria_met,
                "total_criteria": total_criteria,
                "output_resolution": f"{width}x{height}",
                "aspect_ratio": round(actual_aspect_ratio, 3),
                "aspect_ratio_target": round(target_aspect_ratio, 3),
                "duration_seconds": round(output_duration, 1),
                "codec": codec,
                "file_size_mb": round(size_mb, 1)
            }
        }
        
        logger.info(f"Verification result: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Always cleanup temp directory
        cleanup_verification_environment(temp_dir)