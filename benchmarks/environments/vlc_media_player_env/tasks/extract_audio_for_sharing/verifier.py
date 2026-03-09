#!/usr/bin/env python3
"""
Verifier for Extract Audio for Sharing task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    get_video_info,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_audio_for_sharing(traj, env_info, task_info):
    """
    Verify extract audio for sharing task completion.
    
    Checks:
    1. Output file exists
    2. Output is audio-only (no video stream)
    3. Audio codec is MP3
    4. Duration matches source video
    5. Bitrate is reasonable for speech (96-256 kbps)
    6. File size reduction achieved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_audio_')
    
    try:
        # Step 1: Get source video info (for reference duration)
        logger.info("Analyzing source video...")
        
        source_local = os.path.join(temp_dir, "source.mp4")
        try:
            copy_from_env("/tmp/vlc_source_video.mp4", source_local)
        except Exception as e:
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": f"Could not access source video: {e}"}
        
        if not os.path.exists(source_local) or os.path.getsize(source_local) == 0:
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": "Source video not available for comparison"}
        
        source_info = get_video_info(source_local)
        
        if 'error' in source_info:
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": f"Error analyzing source: {source_info['error']}"}
        
        if 'duration' not in source_info:
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": "Could not determine source video duration"}
        
        source_duration = source_info['duration']
        source_size_kb = os.path.getsize(source_local) / 1024
        logger.info(f"Source duration: {source_duration:.2f}s, size: {source_size_kb:.1f} KB")
        
        # Step 2: Check if output file exists
        logger.info("Checking for output audio file...")
        
        output_local = os.path.join(temp_dir, "output.mp3")
        try:
            copy_from_env("/tmp/vlc_extracted_audio.mp3", output_local)
        except Exception as e:
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": f"Output file not found. Did you save the extracted audio to /home/ga/Music/lecture_audio.mp3? Error: {e}"}
        
        if not os.path.exists(output_local) or os.path.getsize(output_local) == 0:
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": 0, "feedback": "Output file is missing or empty. Make sure to extract audio and save to /home/ga/Music/lecture_audio.mp3"}
        
        criteria_met += 1
        feedback_parts.append("✅ Output file exists")
        
        output_size_kb = os.path.getsize(output_local) / 1024
        logger.info(f"Output file size: {output_size_kb:.1f} KB")
        
        # Step 3: Verify output is audio-only (should NOT have video stream)
        logger.info("Verifying output is audio-only...")
        
        video_check = get_video_info(output_local)
        
        # Check if there's a video stream
        if 'width' in video_check and video_check.get('width', 0) > 0:
            feedback_parts.append("❌ Output contains a video stream! You should extract ONLY audio, not convert the entire video.")
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": int((criteria_met / total_criteria) * 100), "feedback": " | ".join(feedback_parts)}
        
        criteria_met += 1
        feedback_parts.append("✅ Audio-only (no video stream)")
        logger.info("Output is audio-only ✓")
        
        # Step 4: Analyze as audio file
        audio_info = get_audio_info(output_local)
        
        if 'error' in audio_info:
            feedback_parts.append(f"❌ Output is not a valid audio file: {audio_info['error']}")
            cleanup_verification_environment(temp_dir)
            return {"passed": False, "score": int((criteria_met / total_criteria) * 100), "feedback": " | ".join(feedback_parts)}
        
        # Step 5: Check codec is MP3
        codec = audio_info.get('codec', '').lower()
        if 'mp3' in codec:
            criteria_met += 1
            feedback_parts.append("✅ Audio codec: MP3")
            logger.info(f"Audio codec: {codec} ✓")
        else:
            feedback_parts.append(f"❌ Audio codec is '{codec}' but should be MP3. Make sure to select MP3 as the output format.")
        
        # Step 6: Check duration matches
        output_duration = audio_info.get('duration', 0)
        
        if output_duration == 0:
            feedback_parts.append("❌ Could not determine output audio duration")
        else:
            duration_diff = abs(output_duration - source_duration)
            
            if duration_diff <= 3.0:
                criteria_met += 1
                feedback_parts.append(f"✅ Duration matches source ({output_duration:.1f}s)")
                logger.info(f"Output duration: {output_duration:.2f}s (matches source within tolerance) ✓")
            else:
                feedback_parts.append(f"❌ Duration mismatch: source={source_duration:.1f}s, output={output_duration:.1f}s (diff: {duration_diff:.1f}s). The audio should have the same duration as the video.")
        
        # Step 7: Check bitrate is reasonable for speech
        bitrate = audio_info.get('bitrate', 0)
        bitrate_kbps = bitrate / 1000 if bitrate > 0 else 0
        
        if bitrate_kbps >= 96 and bitrate_kbps <= 256:
            criteria_met += 1
            feedback_parts.append(f"✅ Bitrate appropriate ({bitrate_kbps:.0f} kbps)")
            logger.info(f"Audio bitrate: {bitrate_kbps:.0f} kbps ✓")
        elif bitrate_kbps < 96:
            feedback_parts.append(f"❌ Audio bitrate ({bitrate_kbps:.0f} kbps) is too low. Use at least 96 kbps for decent speech quality.")
        elif bitrate_kbps > 256:
            feedback_parts.append(f"⚠️ Audio bitrate ({bitrate_kbps:.0f} kbps) is higher than needed. 128-192 kbps is efficient for speech.")
            criteria_met += 0.5  # Partial credit - it works but not optimal
        else:
            feedback_parts.append("❌ Could not determine audio bitrate")
        
        # Step 8: Check file size reduction
        size_ratio = output_size_kb / source_size_kb if source_size_kb > 0 else 1.0
        
        if size_ratio < 0.5:
            criteria_met += 1
            feedback_parts.append(f"✅ File size reduced ({size_ratio*100:.0f}% of source)")
            logger.info(f"File size: {output_size_kb:.1f} KB ({size_ratio*100:.0f}% of source) ✓")
        else:
            feedback_parts.append(f"⚠️ File size reduction insufficient: output is {size_ratio*100:.0f}% of source size. Audio-only MP3 should be much smaller than the original video.")
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        import traceback
        traceback.print_exc()
        cleanup_verification_environment(temp_dir)
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}
    
    finally:
        # Cleanup
        cleanup_verification_environment(temp_dir)
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Pass threshold
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    if passed:
        summary = "\n✓ Successfully extracted audio from video! File is now easy to share and playable on any device."
    else:
        summary = f"\n✗ Audio extraction incomplete or incorrect. Score: {score}%"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback + summary
    }