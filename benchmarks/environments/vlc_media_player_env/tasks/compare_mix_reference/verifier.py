#!/usr/bin/env python3
"""
Verifier for Compare Mix Reference task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_xspf_playlist,
    get_audio_info,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compare_mix_reference(traj, env_info, task_info):
    """
    Verify compare mix reference task completion.
    
    Checks:
    1. Playlist file exists and is parseable
    2. Playlist contains exactly 2 tracks
    3. First track is my_mix.mp3, second is reference_track.mp3 (order matters)
    4. Both audio files exist and are valid
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy and parse playlist
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_mix_comparison_playlist.xspf",
        file_type='playlist'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Playlist not found: {error}"}
    
    criteria_met += 1
    feedback_parts.append("✅ Playlist file exists and is parseable")
    
    playlist_data = file_info.get('data', {})
    items = playlist_data.get('items', [])
    
    if not items:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {"passed": False, "score": 25, "feedback": "Playlist is empty (no tracks found)"}
    
    feedback_parts.append(f"Playlist has {len(items)} items")
    
    # Criterion 2: Check exactly 2 tracks
    if len(items) == 2:
        criteria_met += 1
        feedback_parts.append("✅ Playlist has exactly 2 tracks")
    elif len(items) > 2:
        feedback_parts.append(f"⚠️ Playlist has {len(items)} tracks (expected exactly 2)")
    else:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {"passed": False, "score": 25, "feedback": f"Playlist has only {len(items)} track (expected 2)"}
    
    # Criterion 3: Check track order and names
    track1_location = items[0].get('location', '')
    track2_location = items[1].get('location', '') if len(items) > 1 else ''
    
    # Normalize paths for comparison (get basename)
    from pathlib import Path
    track1_name = Path(track1_location).name if track1_location else ''
    track2_name = Path(track2_location).name if track2_location else ''
    
    logger.info(f"Track 1: {track1_name}")
    logger.info(f"Track 2: {track2_name}")
    
    # Check if first track is the mix
    track1_correct = 'my_mix.mp3' in track1_name.lower()
    track2_correct = 'reference_track.mp3' in track2_name.lower()
    
    if track1_correct and track2_correct:
        criteria_met += 1
        feedback_parts.append("✅ Tracks in correct order (mix → reference)")
    elif 'my_mix.mp3' in track2_name.lower() and 'reference_track.mp3' in track1_name.lower():
        # Tracks are reversed
        feedback_parts.append("⚠️ Tracks in reversed order (reference → mix)")
    elif track1_correct:
        feedback_parts.append("⚠️ Track 1 correct but track 2 incorrect")
    elif track2_correct:
        feedback_parts.append("⚠️ Track 2 correct but track 1 incorrect")
    else:
        feedback_parts.append(f"❌ Wrong tracks: {track1_name}, {track2_name}")
    
    cleanup_verification_environment(file_info.get('temp_dir'))
    
    # Criterion 4: Verify both audio files exist and are valid
    audio_files_valid = 0
    
    # Check my_mix.mp3
    try:
        temp_mix = tempfile.NamedTemporaryFile(delete=False, suffix='.mp3')
        copy_from_env("/tmp/vlc_my_mix.mp3", temp_mix.name)
        
        mix_info = get_audio_info(temp_mix.name)
        if 'error' not in mix_info and mix_info.get('duration', 0) > 0:
            audio_files_valid += 1
            logger.info(f"my_mix.mp3 is valid ({mix_info.get('duration', 0):.1f}s)")
        else:
            logger.warning("my_mix.mp3 may be invalid")
        
        os.unlink(temp_mix.name)
    except Exception as e:
        logger.warning(f"Could not verify my_mix.mp3: {e}")
    
    # Check reference_track.mp3
    try:
        temp_ref = tempfile.NamedTemporaryFile(delete=False, suffix='.mp3')
        copy_from_env("/tmp/vlc_reference_track.mp3", temp_ref.name)
        
        ref_info = get_audio_info(temp_ref.name)
        if 'error' not in ref_info and ref_info.get('duration', 0) > 0:
            audio_files_valid += 1
            logger.info(f"reference_track.mp3 is valid ({ref_info.get('duration', 0):.1f}s)")
        else:
            logger.warning("reference_track.mp3 may be invalid")
        
        os.unlink(temp_ref.name)
    except Exception as e:
        logger.warning(f"Could not verify reference_track.mp3: {e}")
    
    if audio_files_valid == 2:
        criteria_met += 1
        feedback_parts.append("✅ Both audio files accessible and valid")
    elif audio_files_valid == 1:
        feedback_parts.append("⚠️ Only one audio file accessible")
    else:
        feedback_parts.append("❌ Audio files not accessible or invalid")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_mix_compare_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }