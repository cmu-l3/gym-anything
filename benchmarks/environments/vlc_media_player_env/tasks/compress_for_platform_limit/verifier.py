#!/usr/bin/env python3
"""
Verifier for Compress for Platform Limit task

This verifier checks:
1. Output file exists and can be parsed
2. File size is strictly under 10MB (CRITICAL requirement)
3. Format is MP4
4. Duration is preserved (~45 seconds)
5. Video quality is acceptable (resolution, codec, bitrate)
6. Video is playable (has valid properties)
"""

import sys
import os
import logging

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


def verify_compress_for_platform_limit(traj, env_info, task_info):
    """
    Verify the compress for platform limit task.
    
    Args:
        traj: Trajectory data (unused but required by interface)
        env_info: Environment info containing copy_from_env function
        task_info: Task info (unused but required by interface)
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    # Define verification criteria
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Configuration
    container_output = "/tmp/vlc_compressed_output.mp4"
    target_size_mb = 10.0
    target_size_bytes = int(target_size_mb * 1024 * 1024)
    expected_duration = 45.0
    duration_tolerance = 2.0  # ±2 seconds acceptable
    min_width = 480  # Minimum acceptable width for watchability
    min_bitrate = 100000  # 100 kbps minimum to avoid unwatchable video
    
    temp_dir = None
    
    try:
        # Step 1: Check if output file exists and copy it
        logger.info("Step 1: Checking for output file...")
        success, file_info, error = copy_and_parse_media(
            container_output,
            copy_from_env,
            'video'
        )
        
        if not success:
            feedback_parts.append(f"❌ Output file not found or couldn't be copied: {error}")
            feedback_parts.append("   Agent may not have completed the conversion.")
            return {
                "passed": False,
                "score": 0,
                "feedback": "\n".join(feedback_parts)
            }
        
        temp_dir = file_info.get('temp_dir')
        video_data = file_info.get('data', {})
        host_file = file_info.get('filepath')
        
        criteria_met += 1
        feedback_parts.append(f"✅ [1/6] Output file exists: {container_output}")
        logger.info(f"Output file found and copied to {host_file}")
        
        # Step 2: Check file size (CRITICAL requirement)
        logger.info("Step 2: Checking file size...")
        file_size_bytes = video_data.get('size_bytes', 0)
        file_size_mb = file_size_bytes / (1024 * 1024)
        
        feedback_parts.append(f"📊 File size: {file_size_mb:.2f}MB (limit: <{target_size_mb}MB)")
        
        if file_size_bytes >= target_size_bytes:
            bytes_over = file_size_bytes - target_size_bytes
            feedback_parts.append(
                f"❌ [2/6] FAILED: File size {file_size_mb:.2f}MB exceeds {target_size_mb}MB limit"
            )
            feedback_parts.append(
                f"   The file is {bytes_over:,} bytes ({bytes_over/(1024*1024):.2f}MB) too large."
            )
            feedback_parts.append(
                "   Agent needs to reduce bitrate or resolution further."
            )
            # Don't return early - continue checking other criteria for feedback
        else:
            criteria_met += 1
            margin_mb = target_size_mb - file_size_mb
            feedback_parts.append(
                f"✅ [2/6] File size is under {target_size_mb}MB limit ({margin_mb:.2f}MB to spare)"
            )
            logger.info(f"File size check passed: {file_size_mb:.2f}MB < {target_size_mb}MB")
        
        # Step 3: Verify format is MP4
        logger.info("Step 3: Checking video format...")
        video_format = video_data.get('format', '').lower()
        
        if 'mp4' not in video_format and 'mov' not in video_format:
            feedback_parts.append(f"❌ [3/6] Wrong format: {video_format} (expected MP4)")
            logger.warning(f"Format check failed: {video_format}")
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ [3/6] Correct format: MP4")
            logger.info(f"Format check passed: {video_format}")
        
        # Step 4: Check duration is preserved
        logger.info("Step 4: Checking video duration...")
        actual_duration = video_data.get('duration', 0)
        duration_diff = abs(actual_duration - expected_duration)
        
        feedback_parts.append(
            f"⏱️  Duration: {actual_duration:.1f}s (expected: ~{expected_duration}s ±{duration_tolerance}s)"
        )
        
        if actual_duration == 0:
            feedback_parts.append(f"❌ [4/6] Duration could not be determined (video may be corrupt)")
            logger.error("Duration is 0, video may be corrupted")
        elif duration_diff > duration_tolerance:
            feedback_parts.append(
                f"❌ [4/6] Duration mismatch: {duration_diff:.1f}s difference (max: {duration_tolerance}s)"
            )
            feedback_parts.append(
                f"   Expected ~{expected_duration}s, got {actual_duration:.1f}s"
            )
            logger.warning(f"Duration check failed: diff={duration_diff:.1f}s")
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ [4/6] Duration preserved (±{duration_tolerance}s)")
            logger.info(f"Duration check passed: {actual_duration:.1f}s ≈ {expected_duration}s")
        
        # Step 5: Verify video quality is acceptable
        logger.info("Step 5: Checking video quality...")
        width = video_data.get('width', 0)
        height = video_data.get('height', 0)
        codec = video_data.get('codec', '')
        bitrate = video_data.get('bitrate', 0)
        fps = video_data.get('fps', 0)
        
        feedback_parts.append(
            f"📹 Video specs: {width}x{height}, codec: {codec}, bitrate: {bitrate:,} bps"
        )
        
        # Check minimum quality thresholds
        quality_issues = []
        
        if width < min_width:
            quality_issues.append(f"resolution too low ({width}px < {min_width}px width)")
        
        if bitrate > 0 and bitrate < min_bitrate:
            quality_issues.append(f"bitrate too low ({bitrate} bps < {min_bitrate} bps)")
        
        if width == 0 or height == 0:
            quality_issues.append("resolution could not be determined")
        
        if quality_issues:
            feedback_parts.append(
                f"❌ [5/6] Video quality insufficient: {', '.join(quality_issues)}"
            )
            logger.warning(f"Quality check failed: {quality_issues}")
        else:
            criteria_met += 1
            feedback_parts.append(
                f"✅ [5/6] Video quality acceptable: {width}x{height}, {codec}"
            )
            logger.info(f"Quality check passed: {width}x{height}, {bitrate} bps")
        
        # Step 6: Verify codec is reasonable
        logger.info("Step 6: Checking video codec...")
        acceptable_codecs = ['h264', 'h265', 'hevc', 'avc', 'mpeg4', 'x264', 'x265']
        codec_lower = codec.lower()
        
        if not codec:
            feedback_parts.append(f"❌ [6/6] Codec could not be determined (video may be corrupt)")
            logger.error("Codec is empty")
        elif not any(c in codec_lower for c in acceptable_codecs):
            feedback_parts.append(
                f"⚠️  [6/6] Unusual codec: {codec} (expected h264/h265, but may work)"
            )
            criteria_met += 0.5  # Partial credit
            logger.warning(f"Unusual codec: {codec}")
        else:
            criteria_met += 1
            feedback_parts.append(f"✅ [6/6] Good codec choice: {codec}")
            logger.info(f"Codec check passed: {codec}")
        
        # Additional information for feedback
        if criteria_met >= total_criteria * 0.8:  # 80% threshold
            feedback_parts.append("\n🎉 SUCCESS!")
            
            # Calculate compression ratio
            estimated_source_mb = 35.0  # From setup script
            compression_ratio = estimated_source_mb / file_size_mb if file_size_mb > 0 else 0
            
            feedback_parts.append(f"✓ Compressed from ~{estimated_source_mb}MB to {file_size_mb:.2f}MB")
            feedback_parts.append(f"✓ Compression ratio: {compression_ratio:.1f}x")
            feedback_parts.append(f"✓ Video is ready for email/platform sharing")
        else:
            feedback_parts.append("\n❌ TASK INCOMPLETE")
            missing = total_criteria - criteria_met
            feedback_parts.append(f"✗ {missing} criteria not met")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 80  # 80% threshold for medium difficulty
        
        logger.info(f"Final score: {score}% ({criteria_met}/{total_criteria} criteria met)")
        logger.info(f"Task passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        import traceback
        error_trace = traceback.format_exc()
        
        feedback_parts.append(f"\n❌ Verification error: {str(e)}")
        feedback_parts.append("Exception details:")
        feedback_parts.append(error_trace)
        
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),  # Partial credit for criteria met so far
            "feedback": "\n".join(feedback_parts)
        }
        
    finally:
        # Always cleanup temp directory
        if temp_dir:
            logger.info(f"Cleaning up temp directory: {temp_dir}")
            cleanup_verification_environment(temp_dir)


# Alias for consistency with other verifiers
verify_task = verify_compress_for_platform_limit
