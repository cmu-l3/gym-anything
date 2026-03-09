#!/usr/bin/env python3
"""
Verifier for Create Playlist task
"""

import sys
import os
import logging
import tempfile

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vlc_verification_utils import (
    parse_m3u_playlist,
    verify_playlist_contents,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_playlist(traj, env_info, task_info):
    """
    Verify create playlist task completion.
    
    Checks:
    1. Playlist file exists and is parseable
    2. Playlist contains expected media files
    3. Playlist has correct number of items
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Expected items in playlist
    expected_items = [
        "sample_video.mp4",
        "color_test.mp4",
        "sample_audio.mp3"
    ]
    
    # Copy and parse playlist
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_created_playlist.m3u",
        file_type='playlist'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Playlist not found: {error}"}
    
    criteria_met += 1
    feedback_parts.append("✅ Playlist file exists")
    
    playlist_data = file_info.get('data', {})
    items = playlist_data.get('items', [])
    
    if not items:
        cleanup_verification_environment(file_info.get('temp_dir'))
        return {"passed": False, "score": 33, "feedback": "Playlist is empty"}
    
    feedback_parts.append(f"Playlist has {len(items)} items")
    
    # Criterion 2: Check item count
    if len(items) >= 3:
        criteria_met += 1
        feedback_parts.append("✅ Playlist has 3+ items")
    else:
        feedback_parts.append(f"⚠️ Playlist has only {len(items)} items (expected 3+)")
    
    # Criterion 3: Check for expected files
    # Use verification utility
    playlist_path = file_info.get('filepath')
    matches, match_feedback = verify_playlist_contents(
        playlist_path,
        expected_items,
        exact_match=False
    )
    
    if matches:
        criteria_met += 1
        feedback_parts.append(f"✅ {match_feedback}")
    else:
        feedback_parts.append(f"⚠️ {match_feedback}")
    
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
