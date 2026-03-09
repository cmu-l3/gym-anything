#!/usr/bin/env python3
"""
Verifier for Identify Bird Call task
"""

import sys
import os
import logging
import tempfile
import glob

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_identify_bird_call(traj, env_info, task_info):
    """
    Verify bird call identification task completion.
    
    Checks:
    1. Extracted audio file exists
    2. Duration is correct (8-12 seconds)
    3. Audio format is shareable (MP3, WAV, OGG, FLAC)
    4. File size is reasonable (<5 MB)
    5. Sample rate is sufficient for analysis (>22 kHz)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Try to find the output file
    # Check multiple possible locations and extensions
    output_path = None
    found_ext = None
    
    possible_paths = [
        "/tmp/vlc_bird_call_output.mp3",
        "/tmp/vlc_bird_call_output.wav",
        "/tmp/vlc_bird_call_output.ogg",
        "/tmp/vlc_bird_call_output.flac",
        "/tmp/vlc_bird_call_output.m4a",
    ]
    
    for path in possible_paths:
        try:
            temp_dir = tempfile.mkdtemp(prefix='vlc_verify_')
            temp_file = os.path.join(temp_dir, "test_output" + os.path.splitext(path)[1])
            copy_from_env(path, temp_file)
            
            if os.path.exists(temp_file) and os.path.getsize(temp_file) > 1000:  # At least 1KB
                output_path = path
                found_ext = os.path.splitext(path)[1]
                logger.info(f"Found output file: {output_path}")
                break
            
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
        except Exception as e:
            logger.debug(f"Path {path} not found: {e}")
            continue
    
    if not output_path:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ No extracted audio file found. Expected: ~/Recordings/unknown_warbler_call.{mp3,wav,ogg,flac}"
        }
    
    # Set up verification environment
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        output_path,
        file_type='audio'
    )
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Failed to analyze output file: {error}"
        }
    
    try:
        audio_data = file_info.get('data', {})
        
        # Criterion 1: File exists (already verified)
        criteria_met += 1
        feedback_parts.append(f"✅ Audio file exists ({found_ext[1:].upper()})")
        
        # Criterion 2: Verify duration (should be 8-12 seconds)
        duration = audio_data.get('duration', 0)
        if 7.5 <= duration <= 12.5:
            criteria_met += 1
            feedback_parts.append(f"✅ Duration correct: {duration:.1f}s")
        elif 5.0 <= duration <= 15.0:
            criteria_met += 0.5  # Partial credit if close
            feedback_parts.append(f"⚠️ Duration acceptable: {duration:.1f}s (expected 8-12s)")
        else:
            feedback_parts.append(f"❌ Duration incorrect: {duration:.1f}s (expected 8-12s)")
        
        # Criterion 3: Verify file format is shareable
        codec = audio_data.get('codec', '').lower()
        valid_codecs = ['mp3', 'pcm_s16le', 'pcm_s16be', 'pcm_s24le', 'pcm_s24be', 
                       'flac', 'vorbis', 'opus', 'aac', 'wmav2', 'mp2']
        
        if codec in valid_codecs:
            criteria_met += 1
            feedback_parts.append(f"✅ Shareable format: {codec.upper()}")
        elif codec:
            criteria_met += 0.5  # Partial credit for any valid codec
            feedback_parts.append(f"⚠️ Unusual codec: {codec.upper()}")
        else:
            feedback_parts.append("❌ Codec not detected")
        
        # Criterion 4: Verify file size is reasonable (<5 MB)
        size_mb = audio_data.get('size_bytes', 0) / (1024 * 1024)
        if size_mb < 5.0:
            criteria_met += 1
            feedback_parts.append(f"✅ File size OK: {size_mb:.2f} MB")
        else:
            feedback_parts.append(f"⚠️ File too large: {size_mb:.2f} MB (expected <5 MB)")
        
        # Additional check: Sample rate (informational)
        sample_rate = audio_data.get('sample_rate', 0)
        if sample_rate >= 22050:
            feedback_parts.append(f"Sample rate: {sample_rate} Hz (good for analysis)")
        elif sample_rate > 0:
            feedback_parts.append(f"⚠️ Low sample rate: {sample_rate} Hz (may affect identification)")
        
        # Check if file is too long (likely extracted entire recording)
        if duration > 60:
            criteria_met = max(0, criteria_met - 2)  # Penalize heavily
            feedback_parts.append("❌ File too long - likely entire recording, not segment")
        
    finally:
        # Cleanup
        cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_bird_call_completed.txt", temp_marker.name)
        if os.path.exists(temp_marker.name):
            with open(temp_marker.name, 'r') as f:
                content = f.read()
                if "completed" in content.lower():
                    feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    # Add helpful final message
    if passed:
        feedback += " | 🎵 Ready for birding community identification!"
    else:
        feedback += " | 💡 Tip: Extract ~10s segment around 3:45 using Record or Convert features"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
