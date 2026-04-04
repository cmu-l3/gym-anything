#!/usr/bin/env python3
"""
Verifier for Burn Subtitles Permanently task

This verifier checks that subtitles have been permanently burned into the video
frames, creating a self-contained video compatible with devices lacking subtitle
support.
"""

import sys
import os
import logging
import subprocess
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment,
    get_video_info
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_burn_subtitles(traj, env_info, task_info):
    """
    Verify that subtitles have been permanently burned into the video.
    
    Checks:
    1. Output file exists and is valid video
    2. Duration matches expected (~30 seconds)
    3. Resolution preserved (1280x720)
    4. Audio stream present
    5. NO subtitle tracks exist (subtitles are burned into video frames)
    6. File size is reasonable
    
    Returns:
        dict: {passed: bool, score: int, feedback: str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    output_path = "/tmp/vlc_burned_subs_output.mp4"
    
    # Setup: Copy output file from container
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        output_path,
        file_type='video'
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Output file not found or invalid: {error}"
        }
    
    try:
        local_file = file_info['filepath']
        video_info = file_info['data']
        
        # Criterion 1: File exists and is valid
        if 'error' in video_info:
            cleanup_verification_environment(file_info.get('temp_dir'))
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Video parsing failed: {video_info['error']}"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Output file exists and is valid")
        
        # Criterion 2: Duration verification (should be ~30 seconds)
        expected_duration = 30.0
        tolerance = 2.0
        
        if 'duration' not in video_info:
            feedback_parts.append("⚠️ Cannot determine video duration")
        else:
            actual_duration = video_info['duration']
            
            if abs(actual_duration - expected_duration) <= tolerance:
                criteria_met += 1
                feedback_parts.append(f"✅ Duration correct: {actual_duration:.1f}s (expected ~{expected_duration}s)")
            else:
                feedback_parts.append(f"⚠️ Duration mismatch: {actual_duration:.1f}s (expected ~{expected_duration}s ±{tolerance}s)")
        
        # Criterion 3: Resolution verification (should be 1280x720)
        expected_width = 1280
        expected_height = 720
        
        actual_width = video_info.get('width', 0)
        actual_height = video_info.get('height', 0)
        
        if actual_width == expected_width and actual_height == expected_height:
            criteria_met += 1
            feedback_parts.append(f"✅ Resolution preserved: {actual_width}x{actual_height}")
        else:
            feedback_parts.append(f"⚠️ Resolution incorrect: {actual_width}x{actual_height} (expected {expected_width}x{expected_height})")
        
        # Criterion 4: Video codec present
        if video_info.get('codec'):
            feedback_parts.append(f"Video codec: {video_info['codec']}")
        else:
            feedback_parts.append("⚠️ No video codec found")
        
        # Criterion 5: File size sanity check (should be > 100 KB)
        file_size_kb = video_info.get('size_bytes', 0) / 1024
        
        if file_size_kb > 100:
            criteria_met += 1
            feedback_parts.append(f"✅ File size reasonable: {file_size_kb:.1f} KB")
        else:
            feedback_parts.append(f"⚠️ File too small: {file_size_kb:.1f} KB (likely corrupted)")
        
        # Criterion 6: CRITICAL - Verify audio stream exists
        cmd_audio = [
            'ffprobe',
            '-v', 'error',
            '-select_streams', 'a:0',
            '-show_entries', 'stream=codec_name',
            '-of', 'csv=p=0',
            local_file
        ]
        
        try:
            result_audio = subprocess.run(cmd_audio, capture_output=True, text=True, timeout=30)
            
            if result_audio.stdout.strip():
                criteria_met += 1
                feedback_parts.append(f"✅ Audio preserved: {result_audio.stdout.strip()}")
            else:
                feedback_parts.append("⚠️ No audio stream found")
        except subprocess.TimeoutExpired:
            feedback_parts.append("⚠️ Audio check timeout")
        except Exception as e:
            feedback_parts.append(f"⚠️ Audio check error: {str(e)}")
        
        # Criterion 7: CRITICAL - Verify NO subtitle tracks exist
        # This is the key check: if subtitles are burned in, there should be no separate subtitle stream
        cmd_subtitle = [
            'ffprobe',
            '-v', 'error',
            '-select_streams', 's',
            '-show_entries', 'stream=codec_name',
            '-of', 'csv=p=0',
            local_file
        ]
        
        try:
            result_subtitle = subprocess.run(cmd_subtitle, capture_output=True, text=True, timeout=30)
            
            # If there's output, it means subtitle streams exist (BAD - not burned in)
            if result_subtitle.stdout.strip():
                feedback_parts.append(
                    f"❌ FAIL: Subtitles NOT burned in! Found subtitle stream: '{result_subtitle.stdout.strip()}'. "
                    f"Subtitles must be rendered into video frames, not added as separate track."
                )
                # This is critical failure - reduce score significantly
                criteria_met -= 1  # Penalty
            else:
                # No subtitle streams = subtitles are burned into video frames (GOOD)
                criteria_met += 1
                feedback_parts.append("✅ CRITICAL: No subtitle tracks found (subtitles properly burned into video)")
        except subprocess.TimeoutExpired:
            feedback_parts.append("⚠️ Subtitle track check timeout")
        except Exception as e:
            feedback_parts.append(f"⚠️ Subtitle track check error: {str(e)}")
        
        # Ensure criteria_met doesn't go negative
        criteria_met = max(0, criteria_met)
        
        # Calculate final score
        # Adjust total criteria to account for the extra check
        total_criteria = 7  # Updated to include subtitle track check
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        feedback = "\n".join(feedback_parts)
        
        # Add summary
        if passed:
            summary = f"\n\n🎉 SUCCESS: Subtitles successfully burned into video! Video is now playable on any device."
        else:
            summary = f"\n\n❌ Task incomplete: Score {score}% (need 75%)"
        
        feedback = feedback + summary
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except subprocess.TimeoutExpired:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Verification timeout during ffprobe analysis"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Always cleanup temporary files
        if 'temp_dir' in file_info:
            cleanup_verification_environment(file_info.get('temp_dir'))