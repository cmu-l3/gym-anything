#!/usr/bin/env python3
"""
Verifier for Deinterlace Vintage Footage task

Checks:
1. Output file exists and has reasonable size
2. Output duration approximately matches source
3. Output is progressive (not interlaced) - CRITICAL CHECK
4. Output uses modern codec
"""

import sys
import os
import logging
import subprocess
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_video_info,
    copy_and_parse_media,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_deinterlace_vintage_footage(traj, env_info, task_info):
    """
    Verify that interlaced video was properly deinterlaced and saved.
    
    This is the core verification for the deinterlacing task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    output_container_path = "/tmp/vlc_deinterlaced_output.mp4"
    source_container_path = "/tmp/vlc_deinterlace_source.avi"
    
    # Copy output file from container
    success, output_info, error, output_temp_dir = copy_and_parse_media(
        output_container_path, copy_from_env, file_type='video'
    )
    
    if not success:
        return {
            'passed': False,
            'score': 0,
            'reason': f"Output file not found or invalid: {error}",
            'feedback': f"❌ Deinterlaced video not found: {error}"
        }
    
    try:
        # Copy source file for comparison
        source_success, source_info, source_error, source_temp_dir = copy_and_parse_media(
            source_container_path, copy_from_env, file_type='video'
        )
        
        if not source_success:
            cleanup_verification_temp(output_temp_dir)
            return {
                'passed': False,
                'score': 0,
                'reason': f"Source file not accessible: {source_error}",
                'feedback': f"❌ Cannot access source file for comparison: {source_error}"
            }
        
        output_data = output_info['data']
        source_data = source_info['data']
        
        # Criterion 1: Output file exists and has reasonable size
        output_size_bytes = output_data.get('size_bytes', 0)
        output_size_kb = output_size_bytes / 1024
        
        if output_size_bytes < 100 * 1024:  # < 100 KB
            cleanup_verification_temp(output_temp_dir)
            cleanup_verification_temp(source_temp_dir)
            return {
                'passed': False,
                'score': 0,
                'reason': f"Output file too small ({output_size_kb:.1f} KB), likely invalid or corrupt",
                'feedback': f"❌ Output file too small ({output_size_kb:.1f} KB) - conversion may have failed"
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Output file valid ({output_size_kb / 1024:.1f} MB)")
        
        # Criterion 2: Duration approximately matches source
        source_duration = source_data.get('duration', 0)
        output_duration = output_data.get('duration', 0)
        
        if source_duration > 0 and output_duration > 0:
            duration_diff = abs(output_duration - source_duration)
            
            if duration_diff <= 5.0:  # Within 5 seconds tolerance
                criteria_met += 1
                feedback_parts.append(
                    f"✅ Duration matches (source: {source_duration:.1f}s, output: {output_duration:.1f}s)"
                )
            else:
                feedback_parts.append(
                    f"⚠️ Duration mismatch (source: {source_duration:.1f}s, output: {output_duration:.1f}s, diff: {duration_diff:.1f}s)"
                )
        else:
            feedback_parts.append("⚠️ Could not verify duration")
        
        # Criterion 3: CRITICAL - Verify output is progressive (NOT interlaced)
        # This is the main goal of the task
        output_file = output_info['filepath']
        
        try:
            cmd = [
                'ffprobe',
                '-v', 'error',
                '-select_streams', 'v:0',
                '-show_entries', 'stream=field_order',
                '-of', 'default=noprint_wrappers=1:nokey=1',
                output_file
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            field_order = result.stdout.strip()
            
            # Progressive video should have field_order = "progressive" or "unknown" (which often means progressive)
            # Interlaced would be "tt", "bb", "tb", "bt"
            interlaced_patterns = ['tt', 'bb', 'tb', 'bt', 'top', 'bottom']
            is_interlaced = any(pattern in field_order.lower() for pattern in interlaced_patterns)
            is_progressive = field_order in ['progressive', 'unknown', ''] or not is_interlaced
            
            if is_progressive:
                criteria_met += 1
                feedback_parts.append(
                    f"✅ Output is progressive (field_order: {field_order or 'progressive'})"
                )
            else:
                feedback_parts.append(
                    f"❌ Output still appears interlaced (field_order: {field_order}). "
                    f"Deinterlacing filter was not applied during conversion."
                )
        except subprocess.TimeoutExpired:
            feedback_parts.append("⚠️ ffprobe timeout while checking field order")
        except Exception as e:
            logger.warning(f"Could not check field order: {e}")
            feedback_parts.append(f"⚠️ Could not verify progressive scan: {str(e)}")
        
        # Criterion 4: Verify reasonable video codec (modern codec)
        codec = output_data.get('codec', '').lower()
        acceptable_codecs = ['h264', 'h265', 'hevc', 'vp8', 'vp9', 'av1', 'mpeg4']
        
        if codec in acceptable_codecs:
            criteria_met += 1
            feedback_parts.append(f"✅ Modern codec used ({codec})")
        else:
            feedback_parts.append(
                f"⚠️ Unexpected or unknown codec: {codec or 'unknown'} "
                f"(expected: {', '.join(acceptable_codecs)})"
            )
        
        # Build metadata for detailed results
        metadata = {
            'source_duration': source_duration,
            'output_duration': output_duration,
            'output_codec': codec,
            'output_resolution': output_data.get('resolution', 'unknown'),
            'output_size_mb': output_size_kb / 1024,
            'field_order': field_order if 'field_order' in locals() else 'unknown',
            'criteria_met': criteria_met,
            'total_criteria': total_criteria
        }
        
        # Clean up temp directories
        cleanup_verification_temp(output_temp_dir)
        cleanup_verification_temp(source_temp_dir)
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary message
        if passed:
            summary = (
                f"✅ SUCCESS! Video successfully deinterlaced. "
                f"Output is {output_duration:.1f}s, progressive scan, "
                f"codec={codec}. Combing artifacts should be eliminated."
            )
        else:
            summary = (
                f"❌ Task incomplete or incorrect. "
                f"Score: {score}/100 (need ≥75). "
                f"Check that deinterlacing filter was applied during conversion."
            )
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"{summary} | {feedback}",
            "metadata": metadata
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        
        # Clean up if we got here with temp dirs
        if 'output_temp_dir' in locals() and output_temp_dir:
            cleanup_verification_temp(output_temp_dir)
        if 'source_temp_dir' in locals() and source_temp_dir:
            cleanup_verification_temp(source_temp_dir)
        
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "reason": f"Exception during verification: {str(e)}"
        }


# Also support alternative function name for compatibility
verify_task = verify_deinterlace_vintage_footage