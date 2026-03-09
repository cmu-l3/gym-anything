#!/usr/bin/env python3
"""
Verifier for Configure Seamless Loop task
Checks if VLC has been configured for seamless looping playback
"""

import sys
import os
import re
import logging
import tempfile
import shutil
from pathlib import Path
from typing import Tuple, Dict

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_m3u_playlist,
    verify_playlist_contents
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_config(filepath: str) -> Dict[str, str]:
    """Parse VLC configuration file (vlcrc format)."""
    config = {}
    if not os.path.exists(filepath):
        return config
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                # Skip comments, empty lines, and section headers
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                # Parse key=value pairs
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
    
    return config


def parse_qt_interface_config(filepath: str) -> Dict[str, str]:
    """Parse VLC Qt interface configuration (INI format)."""
    config = {}
    if not os.path.exists(filepath):
        return config
    
    try:
        current_section = None
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith(';') or line.startswith('#'):
                    continue
                
                # Section header
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    continue
                
                # Key-value pair
                if '=' in line:
                    key, value = line.split('=', 1)
                    # Store with section prefix for clarity
                    full_key = f"{current_section}.{key.strip()}" if current_section else key.strip()
                    config[full_key] = value.strip()
    except Exception as e:
        logger.error(f"Error parsing Qt interface config: {e}")
    
    return config


def check_loop_configuration(result_dir: str) -> Tuple[bool, str, Dict]:
    """
    Verify VLC is configured for seamless looping.
    
    Returns:
        Tuple of (success, feedback_message, details_dict)
    """
    details = {
        'loop_enabled': False,
        'repeat_enabled': False,
        'playlist_exists': False,
        'playlist_contains_video': False,
        'playlist_valid': False,
        'config_found': False,
        'method_used': None,
        'score': 0.0
    }
    
    feedback_parts = []
    
    # Check main VLC config (vlcrc)
    vlcrc_path = os.path.join(result_dir, 'vlcrc')
    vlc_config = parse_vlc_config(vlcrc_path)
    
    if vlc_config:
        details['config_found'] = True
    
    # Check Qt interface config
    qt_config_path = os.path.join(result_dir, 'vlc-qt-interface.conf')
    qt_config = parse_qt_interface_config(qt_config_path)
    
    # Check playlist file existence and contents
    playlist_path = os.path.join(result_dir, 'stream_loop.m3u')
    
    if os.path.exists(playlist_path):
        details['playlist_exists'] = True
        feedback_parts.append("✅ Playlist file created")
        
        # Parse playlist
        try:
            playlist_items = parse_m3u_playlist(playlist_path)
            
            if playlist_items:
                details['playlist_valid'] = True
                # Check if stream_background.mp4 is in playlist
                has_video = any('stream_background.mp4' in item for item in playlist_items)
                
                if has_video:
                    details['playlist_contains_video'] = True
                    feedback_parts.append("✅ Playlist contains stream_background.mp4")
                else:
                    feedback_parts.append(f"⚠️ Playlist exists but doesn't contain stream_background.mp4 (found: {playlist_items})")
            else:
                feedback_parts.append("⚠️ Playlist file is empty")
        except Exception as e:
            logger.error(f"Error parsing playlist: {e}")
            feedback_parts.append(f"⚠️ Error parsing playlist: {e}")
    else:
        feedback_parts.append("❌ Playlist file 'stream_loop.m3u' not found in /home/ga/Videos/playlists/")
    
    # Check loop/repeat settings in vlcrc
    loop_found = False
    repeat_found = False
    
    if 'loop' in vlc_config:
        loop_value = vlc_config['loop']
        if loop_value in ['1', 'true', 'yes', 'on']:
            details['loop_enabled'] = True
            loop_found = True
            feedback_parts.append("✅ Loop mode enabled in vlcrc")
    
    if 'repeat' in vlc_config:
        repeat_value = vlc_config['repeat']
        if repeat_value in ['1', 'true', 'yes', 'on']:
            details['repeat_enabled'] = True
            repeat_found = True
            feedback_parts.append("✅ Repeat mode enabled in vlcrc")
    
    # Check Qt interface config (more likely to have persistent UI state)
    for key, value in qt_config.items():
        key_lower = key.lower()
        
        if 'loop' in key_lower and 'repeat' not in key_lower:
            # Check if value indicates enabled state
            if value.lower() in ['1', 'true', 'yes', 'on'] or value == '1':
                details['loop_enabled'] = True
                loop_found = True
                feedback_parts.append(f"✅ Loop setting found in Qt config: {key}={value}")
        
        if 'repeat' in key_lower:
            if value.lower() in ['1', 'true', 'yes', 'on'] or value == '1':
                details['repeat_enabled'] = True
                repeat_found = True
                feedback_parts.append(f"✅ Repeat setting found in Qt config: {key}={value}")
    
    # Determine method used
    if loop_found and not repeat_found:
        details['method_used'] = 'loop'
    elif repeat_found and not loop_found:
        details['method_used'] = 'repeat'
    elif loop_found and repeat_found:
        details['method_used'] = 'both'
    
    # Calculate score based on completeness
    score = 0.0
    max_score = 100.0
    
    # Criterion 1: Playlist file created (20 points)
    if details['playlist_exists']:
        score += 20
    
    # Criterion 2: Playlist contains video (25 points)
    if details['playlist_contains_video']:
        score += 25
    
    # Criterion 3: Loop or repeat enabled (40 points)
    if details['loop_enabled'] or details['repeat_enabled']:
        score += 40
    
    # Criterion 4: Both playlist and loop configured (15 bonus points)
    if details['playlist_contains_video'] and (details['loop_enabled'] or details['repeat_enabled']):
        score += 15
    
    details['score'] = score / max_score
    
    # Determine success
    if details['playlist_contains_video'] and (details['loop_enabled'] or details['repeat_enabled']):
        feedback = "✅ SUCCESS: Seamless loop configured correctly!\n" + "\n".join(feedback_parts)
        feedback += f"\n\nConfiguration method: {details['method_used']}"
        return True, feedback, details
    
    # Partial success
    if score >= 60:
        feedback = "⚠️ PARTIAL SUCCESS: Loop configured but incomplete.\n" + "\n".join(feedback_parts)
        feedback += "\n\nMissing components:\n"
        if not details['playlist_contains_video']:
            feedback += "  - Valid playlist file with stream_background.mp4\n"
        if not (details['loop_enabled'] or details['repeat_enabled']):
            feedback += "  - Loop or repeat mode enabled in VLC config\n"
        return False, feedback, details
    
    # Failure
    feedback = "❌ FAILURE: Loop not properly configured.\n"
    if feedback_parts:
        feedback += "\n".join(feedback_parts) + "\n"
    
    feedback += "\n📋 Required steps:\n"
    feedback += "1. Create playlist file 'stream_loop.m3u' in /home/ga/Videos/playlists/\n"
    feedback += "2. Add stream_background.mp4 to the playlist\n"
    feedback += "3. Enable loop mode (Playback → Loop or press 'L')\n"
    feedback += "   OR enable repeat mode (Playback → Repeat or press 'R')\n"
    feedback += "4. Save playlist (Media → Save Playlist to File)\n"
    feedback += "5. Configuration persists automatically\n"
    
    return False, feedback, details


def verify_configure_seamless_loop(traj, env_info, task_info):
    """
    Main verification function called by gym-anything.
    
    Args:
        traj: Trajectory data (not used in this verifier)
        env_info: Environment info dict with 'copy_from_env' function
        task_info: Task info dict
        
    Returns:
        Dict with verification results
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Create temporary directory for results
    temp_dir = tempfile.mkdtemp(prefix='vlc_loop_verify_')
    
    try:
        # Copy all result files from container
        files_to_copy = [
            ("/tmp/task_results/vlcrc", "vlcrc"),
            ("/tmp/task_results/vlc-qt-interface.conf", "vlc-qt-interface.conf"),
            ("/tmp/task_results/stream_loop.m3u", "stream_loop.m3u")
        ]
        
        for container_path, filename in files_to_copy:
            try:
                dest_path = os.path.join(temp_dir, filename)
                copy_from_env(container_path, dest_path)
                logger.info(f"Copied {filename}")
            except Exception as e:
                logger.warning(f"Could not copy {filename}: {e}")
        
        # Run verification on copied files
        success, feedback, details = check_loop_configuration(temp_dir)
        
        # Check completion marker
        try:
            marker_path = os.path.join(temp_dir, "completed.txt")
            copy_from_env("/tmp/vlc_seamless_loop_completed.txt", marker_path)
            logger.info("Task completion marker found")
        except Exception:
            logger.warning("Completion marker not found")
        
        return {
            'passed': success,
            'score': int(details['score'] * 100),
            'feedback': feedback,
            'details': details
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            try:
                shutil.rmtree(temp_dir)
                logger.debug(f"Cleaned up temp directory: {temp_dir}")
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")
