#!/usr/bin/env python3
"""
Verifier for Batch Video Library Verification task (batch_verify_library@1)

Validates that agent created a playlist containing all archive videos.
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_m3u_playlist,
    parse_xspf_playlist,
    verify_playlist_contents,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_batch_verify_library(traj, env_info, task_info):
    """
    Verify batch video library verification task completion.
    
    Checks:
    1. Playlist file exists and is parseable (20 points)
    2. Playlist has content (10 points)
    3. Playlist has correct number of items - 5 videos (30 points)
    4. Playlist contains all expected archive files (40 points)
    
    Args:
        traj: Trajectory information
        env_info: Environment info with copy_from_env function
        task_info: Task information
        
    Returns:
        Dict with passed (bool), score (int 0-100), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    criteria_met = 0.0
    total_criteria = 10.0  # Using decimal for partial credit
    feedback_parts = []
    
    # Expected video files in the archive
    expected_files = [
        "lecture_01_intro.mp4",
        "lecture_02_methodology.mp4",
        "lecture_03_results.mp4",
        "lecture_04_discussion.mp4",
        "lecture_05_conclusion.mp4"
    ]
    
    # Criterion 1: Playlist file exists (2 points)
    playlist_exists = False
    playlist_path = None
    temp_playlist = tempfile.NamedTemporaryFile(delete=False, suffix='.m3u')
    
    try:
        copy_from_env("/tmp/vlc_batch_verify_playlist.m3u", temp_playlist.name)
        playlist_path = temp_playlist.name
        
        # Check if file has content
        file_size = os.path.getsize(playlist_path)
        
        if file_size > 0:
            playlist_exists = True
            criteria_met += 2.0
            feedback_parts.append(f"✅ Playlist file exists ({file_size} bytes)")
        else:
            feedback_parts.append("❌ Playlist file is empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
    except Exception as e:
        logger.error(f"Failed to copy playlist file: {e}")
        feedback_parts.append("❌ Playlist file not found at expected location")
        
        # Cleanup and return early
        try:
            os.unlink(temp_playlist.name)
        except:
            pass
        
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Criterion 2: Playlist is parseable (1 point)
    playlist_items = []
    playlist_format = None
    
    try:
        # Try parsing as M3U first
        with open(playlist_path, 'r', encoding='utf-8', errors='ignore') as f:
            first_line = f.readline().strip()
        
        # Check if it's XSPF (XML-based)
        if first_line.startswith('<?xml') or '<playlist' in first_line:
            playlist_format = 'XSPF'
            try:
                xspf_items = parse_xspf_playlist(playlist_path)
                playlist_items = [item.get('location', '') for item in xspf_items if item.get('location')]
            except Exception as e:
                logger.error(f"Failed to parse XSPF playlist: {e}")
                feedback_parts.append("❌ Failed to parse XSPF playlist")
        else:
            # Parse as M3U
            playlist_format = 'M3U'
            try:
                playlist_items = parse_m3u_playlist(playlist_path)
            except Exception as e:
                logger.error(f"Failed to parse M3U playlist: {e}")
                feedback_parts.append("❌ Failed to parse M3U playlist")
        
        if playlist_items:
            criteria_met += 1.0
            feedback_parts.append(f"✅ Playlist parsed successfully ({playlist_format} format)")
        else:
            feedback_parts.append("❌ Playlist parsing returned no items")
    except Exception as e:
        logger.error(f"Error parsing playlist: {e}")
        feedback_parts.append(f"❌ Error parsing playlist: {str(e)}")
    
    # Early exit if no items parsed
    if not playlist_items:
        cleanup_temp_file(temp_playlist.name)
        score = int((criteria_met / total_criteria) * 100)
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    feedback_parts.append(f"Playlist has {len(playlist_items)} items")
    
    # Criterion 3: Playlist has correct number of items (3 points)
    if len(playlist_items) == len(expected_files):
        criteria_met += 3.0
        feedback_parts.append(f"✅ Correct item count ({len(expected_files)} videos)")
    elif len(playlist_items) > len(expected_files):
        # Partial credit if has extra items but includes all expected
        criteria_met += 1.5
        feedback_parts.append(f"⚠️ Playlist has extra items ({len(playlist_items)} vs {len(expected_files)} expected)")
    elif len(playlist_items) >= 3:
        # Some credit for having most files
        partial = (len(playlist_items) / len(expected_files)) * 3.0
        criteria_met += partial
        feedback_parts.append(f"⚠️ Incomplete playlist ({len(playlist_items)}/{len(expected_files)} videos)")
    else:
        feedback_parts.append(f"❌ Too few items ({len(playlist_items)}/{len(expected_files)} expected)")
    
    # Criterion 4: All expected files are present (4 points)
    found_files = []
    missing_files = []
    
    for expected in expected_files:
        # Check if any playlist item contains this filename
        # Handle both absolute paths and relative paths
        found = False
        for item in playlist_items:
            # Extract just the filename from the path
            item_filename = os.path.basename(item) if item else ''
            
            if expected in item or expected == item_filename:
                found = True
                found_files.append(expected)
                break
        
        if not found:
            missing_files.append(expected)
    
    if not missing_files:
        # All files found
        criteria_met += 4.0
        feedback_parts.append(f"✅ All {len(expected_files)} archive videos included")
    elif len(found_files) >= 4:
        # Most files found
        partial = (len(found_files) / len(expected_files)) * 4.0
        criteria_met += partial
        feedback_parts.append(f"⚠️ Missing {len(missing_files)} file(s): {', '.join(missing_files[:2])}")
    else:
        # Few files found
        partial = (len(found_files) / len(expected_files)) * 4.0
        criteria_met += partial
        feedback_parts.append(f"❌ Missing files: {', '.join(missing_files[:3])}")
    
    # Bonus: Check if saved with correct filename (not counted in score, just feedback)
    try:
        metadata_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/vlc_batch_verify_metadata.json", metadata_temp.name)
        
        import json
        with open(metadata_temp.name, 'r') as f:
            metadata = json.load(f)
        
        if metadata.get('playlist_exists'):
            feedback_parts.append("✅ Saved at correct location")
        
        os.unlink(metadata_temp.name)
    except Exception as e:
        logger.debug(f"Could not check metadata: {e}")
    
    # Cleanup
    cleanup_temp_file(temp_playlist.name)
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # Need 80% to pass
    
    # Build final feedback message
    if passed:
        feedback = f"✅ Task completed successfully!\n\n{chr(10).join(feedback_parts)}\n\n📊 Final score: {score}/100"
    else:
        feedback = f"❌ Task incomplete\n\n{chr(10).join(feedback_parts)}\n\n📊 Final score: {score}/100"
    
    # Format feedback for single line if needed
    feedback_oneline = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_oneline
    }


def cleanup_temp_file(filepath):
    """Helper to safely cleanup temp files"""
    try:
        if filepath and os.path.exists(filepath):
            os.unlink(filepath)
    except Exception as e:
        logger.debug(f"Could not cleanup temp file {filepath}: {e}")
