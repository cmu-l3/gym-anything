#!/usr/bin/env python3
"""
Verifier for Extract Audio Podcast task
Checks that audio was correctly extracted from video to MP3 format
"""

import json
import logging
import os
import sys
from pathlib import Path
from typing import Any, Dict, Tuple

# Add utils to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    get_audio_info,
    get_video_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_extract_audio_podcast(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that audio was correctly extracted from video to MP3.
    
    Checks:
    1. MP3 file exists in output directory
    2. File is valid MP3 format (codec verification)
    3. Audio-only (no video stream)
    4. Duration matches source video (±2s tolerance)
    5. Bitrate in reasonable range (96-256 kbps)
    6. File size is reasonable (>500KB for 2-minute audio)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        Dict with passed, score, feedback, and metadata
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available",
            "metadata": {"error": "copy_from_env not provided"}
        }
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    metadata = {
        "task_id": "extract_audio_podcast@1",
        "checks": {}
    }
    
    # ===== Check 1: Audio file exists and is parseable =====
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_extracted_audio.mp3",
        file_type='audio'
    )
    
    if not success:
        feedback_parts.append(f"❌ No MP3 file found in output directory: {error}")
        metadata["checks"]["file_exists"] = False
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts),
            "metadata": metadata
        }
    
    criteria_met += 1
    audio_filepath = file_info.get('filepath', '')
    feedback_parts.append(f"✅ Found extracted audio file")
    metadata["checks"]["file_exists"] = True
    
    # ===== Check 2: File size reasonable =====
    file_size_kb = Path(audio_filepath).stat().st_size / 1024
    metadata["output_size_kb"] = round(file_size_kb, 2)
    
    if file_size_kb < 500:
        feedback_parts.append(f"❌ Audio file too small ({file_size_kb:.1f} KB) - likely corrupted")
        metadata["checks"]["file_size"] = False
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": "\n".join(feedback_parts),
            "metadata": metadata
        }
    
    criteria_met += 1
    feedback_parts.append(f"✅ File size reasonable: {file_size_kb:.1f} KB")
    metadata["checks"]["file_size"] = True
    
    # ===== Check 3: Get audio information and verify MP3 codec =====
    audio_data = file_info.get('data', {})
    
    if 'error' in audio_data:
        feedback_parts.append(f"❌ Failed to analyze audio: {audio_data['error']}")
        metadata["checks"]["audio_analysis"] = False
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": "\n".join(feedback_parts),
            "metadata": metadata
        }
    
    metadata["audio_info"] = audio_data
    
    # Verify MP3 codec
    codec = audio_data.get('codec', '').lower()
    if 'mp3' not in codec:
        feedback_parts.append(f"❌ Wrong audio codec: {codec} (expected mp3)")
        metadata["checks"]["codec"] = False
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": "\n".join(feedback_parts),
            "metadata": metadata
        }
    
    criteria_met += 1
    feedback_parts.append(f"✅ Correct codec: {codec}")
    metadata["checks"]["codec"] = True
    
    # ===== Check 4: Verify it's audio-only (no video stream) =====
    # Try to get video info - should fail or return no video stream
    video_check = get_video_info(audio_filepath)
    has_video = video_check.get('width', 0) > 0
    
    if has_video:
        feedback_parts.append("⚠️ Output contains video stream (should be audio-only)")
        metadata["checks"]["audio_only"] = False
    else:
        criteria_met += 1
        feedback_parts.append("✅ Output is audio-only (no video stream)")
        metadata["checks"]["audio_only"] = True
    
    # ===== Check 5: Verify audio properties =====
    duration = audio_data.get('duration', 0)
    bitrate = audio_data.get('bitrate', 0)
    sample_rate = audio_data.get('sample_rate', 0)
    channels = audio_data.get('channels', 0)
    
    feedback_parts.append(f"📊 Audio properties:")
    feedback_parts.append(f"   - Duration: {duration:.1f} seconds")
    feedback_parts.append(f"   - Bitrate: {bitrate // 1000} kbps")
    feedback_parts.append(f"   - Sample rate: {sample_rate} Hz")
    feedback_parts.append(f"   - Channels: {channels}")
    
    # Check bitrate range (96-256 kbps is reasonable for podcasts)
    bitrate_kbps = bitrate // 1000
    if 96 <= bitrate_kbps <= 256:
        criteria_met += 1
        feedback_parts.append(f"✅ Bitrate in good range for podcasts")
        metadata["checks"]["bitrate"] = True
    else:
        feedback_parts.append(f"⚠️ Bitrate unusual: {bitrate_kbps} kbps (expected 96-256)")
        metadata["checks"]["bitrate"] = False
    
    # ===== Check 6: Compare duration with source video =====
    # Try to load and compare with source video
    source_success, source_info, source_error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_source_video.mp4",
        file_type='video'
    )
    
    if source_success:
        source_data = source_info.get('data', {})
        source_duration = source_data.get('duration', 0)
        
        metadata["source_duration"] = source_duration
        metadata["output_duration"] = duration
        
        if source_duration > 0:
            duration_diff = abs(duration - source_duration)
            metadata["duration_difference"] = round(duration_diff, 2)
            
            if duration_diff <= 2.0:
                criteria_met += 1
                feedback_parts.append(f"✅ Duration matches source (±{duration_diff:.1f}s)")
                metadata["checks"]["duration_match"] = True
            else:
                feedback_parts.append(f"⚠️ Duration differs from source by {duration_diff:.1f}s")
                metadata["checks"]["duration_match"] = False
        else:
            feedback_parts.append("⚠️ Could not determine source duration")
            metadata["checks"]["duration_match"] = False
        
        cleanup_verification_environment(source_info.get('temp_dir'))
    else:
        # Without source comparison, at least check duration is reasonable (>60s)
        if duration >= 60:
            criteria_met += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ Source not available, but duration seems reasonable ({duration:.1f}s)")
            metadata["checks"]["duration_match"] = "partial"
        else:
            feedback_parts.append(f"⚠️ Duration seems too short ({duration:.1f}s)")
            metadata["checks"]["duration_match"] = False
    
    # Cleanup audio temp directory
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # ===== Calculate overall success =====
    # Critical checks that must pass
    critical_checks = [
        metadata["checks"]["file_exists"],
        metadata["checks"]["file_size"],
        metadata["checks"]["codec"],
    ]
    
    # Quality checks (nice to have)
    quality_checks = [
        metadata["checks"].get("audio_only", False),
        metadata["checks"].get("bitrate", False),
        metadata["checks"].get("duration_match", False) is True,
    ]
    
    # Determine final score
    if all(critical_checks):
        if all(quality_checks):
            reward = 1.0
            feedback_parts.insert(0, "🎉 SUCCESS: Audio extracted perfectly!")
        elif sum(quality_checks) >= 2:
            reward = 0.8
            feedback_parts.insert(0, "✅ SUCCESS: Audio extracted with minor issues")
        else:
            reward = 0.7
            feedback_parts.insert(0, "✅ PARTIAL SUCCESS: Audio extracted but with quality concerns")
    else:
        reward = max(0.2, criteria_met / total_criteria * 0.5)
        feedback_parts.insert(0, "❌ FAILED: Audio extraction incomplete or incorrect")
    
    score = int(reward * 100)
    passed = score >= 70
    
    metadata["criteria_met"] = criteria_met
    metadata["total_criteria"] = total_criteria
    metadata["raw_score"] = round(criteria_met / total_criteria, 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "metadata": metadata
    }
