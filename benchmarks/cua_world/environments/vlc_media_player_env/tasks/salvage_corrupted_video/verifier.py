#!/usr/bin/env python3
"""
Verifier for Salvage Corrupted Video task
Checks if user successfully recovered playable content from corrupted video file
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


def verify_salvage_corrupted_video(traj, env_info, task_info):
    """
    Verify that corrupted video was successfully salvaged using VLC.
    
    Checks:
    1. Output file exists and is non-empty
    2. Output file is valid and playable (no corruption errors)
    3. Output uses correct codecs (H.264)
    4. Output has reasonable duration (at least 15 seconds recovered)
    5. Output has proper resolution and format
    
    Args:
        traj: Agent trajectory
        env_info: Environment information including copy_from_env function
        task_info: Task configuration
        
    Returns:
        dict with 'passed' (bool), 'score' (int), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Check if summary exists
    temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_salvage_summary.json", temp_summary.name)
        with open(temp_summary.name, 'r') as f:
            summary = json.load(f)
        
        if not summary.get('output_found', False):
            logger.warning("Output not found according to summary")
        
        os.unlink(temp_summary.name)
    except Exception as e:
        logger.warning(f"Could not read summary: {e}")
    
    # Criterion 1: Check if recovered video exists and analyze it
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_salvaged_video.mp4",
        file_type='video'
    )
    
    if not success:
        return {
            'passed': False,
            'score': 0,
            'feedback': (
                "❌ Recovered video file not found.\n"
                f"Error: {error}\n\n"
                "Expected location: /home/ga/Videos/recovered/interview_salvaged.mp4\n"
                "Did you use VLC's Convert/Save feature (Media → Convert/Save or Ctrl+R)?\n"
                "Make sure to:\n"
                "  1. Add the corrupted file as source\n"
                "  2. Select 'Convert' (not just 'Play')\n"
                "  3. Choose H.264+AAC profile\n"
                "  4. Set correct output destination\n"
                "  5. Let conversion complete"
            )
        }
    
    # File exists
    criteria_met += 1
    feedback_parts.append("✅ Recovered video file exists")
    
    video_data = file_info.get('data', {})
    
    # Check for parsing errors
    if 'error' in video_data:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            'passed': False,
            'score': 25,
            'feedback': (
                f"❌ Recovered video appears corrupted or invalid.\n"
                f"Parse error: {video_data['error']}\n\n"
                "The output file exists but cannot be analyzed properly.\n"
                "This suggests the conversion may not have completed successfully.\n"
                "Make sure VLC finished processing the entire recoverable portion."
            )
        }
    
    # Check file is not empty/too small
    recovered_size = video_data.get('size_bytes', 0)
    if recovered_size < 10000:  # Less than 10KB is too small
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            'passed': False,
            'score': 25,
            'feedback': (
                f"❌ Recovered video file is too small ({recovered_size} bytes).\n"
                "This suggests the conversion failed or produced an empty file.\n"
                "Did the VLC conversion process complete successfully?"
            )
        }
    
    # Criterion 2: Check video codec (should be H.264)
    codec = video_data.get('codec', '').lower()
    if 'h264' in codec or 'avc' in codec:
        criteria_met += 1
        feedback_parts.append(f"✅ Video codec is H.264 ({codec.upper()})")
    else:
        feedback_parts.append(
            f"⚠️ Video codec is '{codec}' instead of H.264. "
            "Expected: Use 'Video - H.264 + AAC (MP4)' conversion profile."
        )
    
    # Criterion 3: Check duration (should have recovered at least 15-20 seconds)
    duration = video_data.get('duration', 0)
    if duration >= 15.0:
        criteria_met += 1
        feedback_parts.append(f"✅ Recovered {duration:.1f} seconds of playable content")
    elif duration >= 10.0:
        criteria_met += 0.5
        feedback_parts.append(
            f"⚠️ Recovered {duration:.1f} seconds (acceptable, but less than expected 15+ seconds)"
        )
    else:
        feedback_parts.append(
            f"❌ Only {duration:.1f} seconds recovered - this seems too short. "
            "The corrupted file should have ~20-22 seconds of playable content before damage."
        )
    
    # Criterion 4: Check resolution and format
    width = video_data.get('width', 0)
    height = video_data.get('height', 0)
    file_format = video_data.get('format', '')
    
    resolution_ok = width >= 640 and height >= 480
    format_ok = 'mp4' in file_format.lower() or 'mov' in file_format.lower()
    
    if resolution_ok and format_ok:
        criteria_met += 1
        feedback_parts.append(
            f"✅ Format and resolution correct ({width}x{height}, {file_format.upper()})"
        )
    elif resolution_ok:
        criteria_met += 0.5
        feedback_parts.append(
            f"⚠️ Resolution OK ({width}x{height}) but format is '{file_format}' instead of MP4"
        )
    elif format_ok:
        criteria_met += 0.5
        feedback_parts.append(
            f"⚠️ Format OK ({file_format.upper()}) but resolution is low ({width}x{height})"
        )
    else:
        feedback_parts.append(
            f"⚠️ Format '{file_format}' and/or resolution ({width}x{height}) may indicate issues"
        )
    
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    if passed:
        feedback = (
            "✅ Successfully recovered video from corrupted file!\n\n"
            "Verification results:\n" +
            "\n".join(f"  • {part}" for part in feedback_parts) +
            f"\n\n📊 Statistics:\n"
            f"  • Recovered file size: {recovered_size / 1024:.1f} KB\n"
            f"  • Duration: {duration:.1f} seconds\n"
            f"  • Resolution: {width}x{height}\n"
            f"  • Codec: {codec.upper()}\n"
            f"  • Format: {file_format.upper()}\n\n"
            "🎯 You successfully used VLC's error-tolerant playback and conversion\n"
            "   features to salvage usable content from a damaged file."
        )
    else:
        feedback = (
            "❌ Video recovery incomplete or has quality issues.\n\n"
            "Issues found:\n" +
            "\n".join(f"  • {part}" for part in feedback_parts if '❌' in part or '⚠️' in part) +
            "\n\nSuccessful checks:\n" +
            "\n".join(f"  • {part}" for part in feedback_parts if '✅' in part) +
            "\n\n💡 Tips:\n"
            "  • Use Media → Convert/Save (Ctrl+R)\n"
            "  • Select 'Convert' not 'Play'\n"
            "  • Choose 'Video - H.264 + AAC (MP4)' profile\n"
            "  • Let conversion complete fully\n"
            "  • VLC error messages during conversion are expected"
        )
    
    return {
        'passed': passed,
        'score': score,
        'feedback': feedback
    }
