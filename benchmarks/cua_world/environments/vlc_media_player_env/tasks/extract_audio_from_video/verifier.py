#!/usr/bin/env python3
"""
Verifier for Extract Audio from Video task

Verification strategy:
1. Check output file exists and is accessible
2. Verify format is MP3 (audio-only, no video stream)
3. Verify audio codec is mp3
4. Verify bitrate is approximately 192 kbps (180-204 kbps range)
5. Verify duration matches source video (±1 second tolerance)
6. Verify file is valid and not corrupted
7. Verify audio properties (stereo, reasonable sample rate)
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
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_audio(traj, env_info, task_info):
    """
    Verify extract audio from video task completion.
    
    Checks:
    1. Output file exists and is accessible
    2. Format is MP3 (audio codec)
    3. Audio-only (no video stream)
    4. Bitrate is approximately 192 kbps (180-204 kbps acceptable)
    5. Duration matches source video
    6. File is valid and playable
    7. Audio properties correct (stereo, sample rate)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5  # 5 main criteria with weighted scoring
    feedback_parts = []
    
    # Source video expected duration (approximately 45 seconds)
    expected_duration = 45.0
    
    # Try to get actual source duration from completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_extract_audio_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
            for line in content.split('\n'):
                if 'source_duration=' in line:
                    try:
                        expected_duration = float(line.split('=')[1].strip())
                        logger.info(f"Source duration from marker: {expected_duration}s")
                    except:
                        pass
        os.unlink(temp_marker.name)
    except Exception as e:
        logger.warning(f"Could not read completion marker: {e}")
    
    # Copy and parse audio file
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_extracted_audio.mp3",
        file_type='audio'
    )
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"❌ Output file not found or not accessible: {error}"
        }
    
    # Criterion 1: File exists and is accessible
    criteria_met += 1
    feedback_parts.append("✅ Output file exists")
    
    audio_data = file_info.get('data', {})
    
    # Check for parsing errors
    if 'error' in audio_data:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": 20,
            "feedback": f"❌ Could not parse audio file: {audio_data['error']}"
        }
    
    # Criterion 2: Verify codec is MP3
    codec = audio_data.get('codec', '').lower()
    if codec == 'mp3':
        criteria_met += 1
        feedback_parts.append(f"✅ Audio codec: MP3")
    else:
        feedback_parts.append(f"❌ Wrong codec: {codec} (expected: mp3)")
    
    # Criterion 3: Ensure no video stream (audio-only file)
    # Check if file has video stream by trying to get video info
    video_data = get_video_info(file_info.get('filepath'))
    has_video = video_data.get('width', 0) > 0 or video_data.get('height', 0) > 0
    
    if not has_video:
        criteria_met += 1
        feedback_parts.append("✅ Audio-only (no video stream)")
    else:
        feedback_parts.append(f"❌ File contains video stream (should be audio-only)")
    
    # Criterion 4: Verify bitrate (192 kbps ± 10 kbps)
    bitrate = audio_data.get('bitrate', 0)
    bitrate_kbps = bitrate / 1000 if bitrate > 0 else 0
    
    # Target: 192 kbps, acceptable range: 180-204 kbps
    target_bitrate = 192
    min_bitrate = 180
    max_bitrate = 204
    
    if min_bitrate <= bitrate_kbps <= max_bitrate:
        criteria_met += 1
        feedback_parts.append(f"✅ Bitrate: {bitrate_kbps:.0f} kbps (target: 192 kbps)")
    elif bitrate_kbps > 0:
        # Partial credit if bitrate is reasonable but not in target range
        if 128 <= bitrate_kbps <= 256:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Bitrate: {bitrate_kbps:.0f} kbps (acceptable but not 192±10 kbps)")
        else:
            feedback_parts.append(f"❌ Bitrate: {bitrate_kbps:.0f} kbps (expected: 180-204 kbps)")
    else:
        feedback_parts.append("❌ Bitrate not detected")
    
    # Criterion 5: Verify duration matches source (±1 second tolerance)
    output_duration = audio_data.get('duration', 0)
    
    if output_duration > 0:
        duration_diff = abs(output_duration - expected_duration)
        
        if duration_diff <= 1.0:
            criteria_met += 1
            feedback_parts.append(f"✅ Duration: {output_duration:.1f}s (matches source: {expected_duration:.1f}s)")
        elif duration_diff <= 3.0:
            # Partial credit if close
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Duration: {output_duration:.1f}s (source: {expected_duration:.1f}s, diff: {duration_diff:.1f}s)")
        else:
            feedback_parts.append(f"❌ Duration mismatch: {output_duration:.1f}s (expected: ~{expected_duration:.1f}s)")
    else:
        feedback_parts.append("❌ Duration not detected")
    
    # Additional checks (for feedback, not scored):
    
    # Check channels (should be stereo = 2)
    channels = audio_data.get('channels', 0)
    if channels == 2:
        feedback_parts.append("✅ Stereo (2 channels)")
    elif channels > 0:
        feedback_parts.append(f"⚠️ Channels: {channels} (expected: 2 for stereo)")
    
    # Check sample rate (should be 44100 or similar)
    sample_rate = audio_data.get('sample_rate', 0)
    if sample_rate >= 44100:
        feedback_parts.append(f"✅ Sample rate: {sample_rate} Hz")
    elif sample_rate > 0:
        feedback_parts.append(f"⚠️ Sample rate: {sample_rate} Hz (typical: 44100 Hz)")
    
    # Check file size (should be reasonable for ~45s at 192kbps)
    # Approximate calculation: 192 kbps * 45 seconds = 1080 KB ≈ 1.05 MB
    size_bytes = audio_data.get('size_bytes', 0)
    size_mb = size_bytes / (1024 * 1024) if size_bytes > 0 else 0
    
    # Minimum reasonable size: at least 0.8 MB for 45 seconds
    if size_mb >= 0.8:
        feedback_parts.append(f"✅ File size: {size_mb:.2f} MB")
    elif size_mb > 0:
        feedback_parts.append(f"⚠️ File size: {size_mb:.2f} MB (may be too small)")
    
    # Cleanup
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }