#!/usr/bin/env python3
"""
Verifier for Stream Network Media task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_m3u_playlist,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_stream_network_media(traj, env_info, task_info):
    """
    Verify stream network media task completion.
    
    Checks:
    1. VLC was playing a network stream (not local file)
    2. Playback continued for at least 10 seconds
    3. Playlist file was created
    4. Playlist contains the stream URL
    
    Returns:
        dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    # Copy stream result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_stream_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying stream result: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Error copying stream result: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        current_media = result.get('current_media', '')
        is_network_stream = result.get('is_network_stream', False)
        playback_state = result.get('playback_state', 'unknown')
        playback_position = result.get('playback_position', 0)
        playlist_exists = result.get('playlist_exists', False)
        
        # Criterion 1: VLC playing network stream (25 points)
        if is_network_stream and 'localhost:8080' in current_media:
            criteria_met += 1
            feedback_parts.append(f"✅ Network stream playing (25/25)")
        elif is_network_stream:
            criteria_met += 0.6
            feedback_parts.append(f"⚠️ Network stream but wrong URL (15/25)")
        else:
            feedback_parts.append(f"❌ No network stream detected (0/25)")
        
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading stream result: {str(e)}"
        }
    
    # Criterion 2: Sustained playback >10 seconds (35 points)
    if playback_state == 'playing' and playback_position >= 10:
        criteria_met += 1
        feedback_parts.append(f"✅ Sustained playback: {playback_position}s (35/35)")
    elif playback_state == 'playing' and playback_position > 5:
        criteria_met += 0.6
        feedback_parts.append(f"⚠️ Playing but <10s: {playback_position}s (21/35)")
    elif playback_position >= 10:
        criteria_met += 0.5
        feedback_parts.append(f"⚠️ Played 10s+ but not active: {playback_position}s (18/35)")
    else:
        feedback_parts.append(f"❌ Insufficient playback: {playback_position}s (0/35)")
    
    # Criterion 3: Playlist file created (25 points)
    if playlist_exists:
        temp_playlist = tempfile.NamedTemporaryFile(delete=False, suffix='.m3u')
        
        try:
            copy_from_env("/tmp/vlc_stream_playlist.m3u", temp_playlist.name)
            
            # Check file size
            playlist_size = os.path.getsize(temp_playlist.name)
            if playlist_size > 10:  # At least 10 bytes
                criteria_met += 1
                feedback_parts.append(f"✅ Playlist created ({playlist_size} bytes) (25/25)")
                
                # Criterion 4: Playlist contains stream URL (15 points)
                try:
                    with open(temp_playlist.name, 'r', encoding='utf-8') as f:
                        playlist_content = f.read()
                    
                    # Check if playlist contains the stream URL
                    if 'localhost:8080' in playlist_content and 'test_stream' in playlist_content:
                        criteria_met += 1
                        feedback_parts.append("✅ Playlist contains stream URL (15/15)")
                    elif 'http://' in playlist_content or 'https://' in playlist_content:
                        criteria_met += 0.5
                        feedback_parts.append("⚠️ Playlist has URL but not expected one (8/15)")
                    else:
                        feedback_parts.append("❌ Playlist missing stream URL (0/15)")
                    
                except Exception as e:
                    logger.warning(f"Could not parse playlist: {e}")
                    feedback_parts.append("⚠️ Could not verify playlist content (0/15)")
            else:
                criteria_met += 0.4
                feedback_parts.append("⚠️ Playlist exists but is empty (10/25)")
            
            os.unlink(temp_playlist.name)
            
        except Exception as e:
            logger.error(f"Error reading playlist: {e}")
            feedback_parts.append(f"⚠️ Playlist exists but could not read (10/25)")
    else:
        feedback_parts.append("❌ Playlist file not found (0/25)")
        feedback_parts.append("❌ Cannot verify playlist content (0/15)")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 60
    
    # Compile feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n📊 Final Score: {score}/100"
    
    if score >= 85:
        feedback += " - ⭐ EXCELLENT"
    elif score >= 60:
        feedback += " - ✅ PASSING"
    else:
        feedback += " - ❌ NEEDS IMPROVEMENT"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }