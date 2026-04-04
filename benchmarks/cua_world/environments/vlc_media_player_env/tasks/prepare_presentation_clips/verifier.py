#!/usr/bin/env python3
"""
Verifier for prepare_presentation_clips@1 task
Checks that presentation playlist is correctly configured with start times
"""

import sys
import os
import logging
import tempfile
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Dict, List, Tuple, Optional

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_xspf_with_start_times(filepath: str) -> List[Dict[str, Any]]:
    """
    Parse XSPF playlist and extract track information including start times.
    
    Args:
        filepath: Path to XSPF file
        
    Returns:
        List of dicts with track info: {location, title, start_time}
    """
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # XSPF namespace
        namespaces = {
            'xspf': 'http://xspf.org/ns/0/',
            'vlc': 'http://www.videolan.org/vlc/playlist/ns/0/'
        }
        
        tracks = []
        
        # Try with namespace first
        track_elements = root.findall('.//xspf:track', namespaces)
        if not track_elements:
            # Try without namespace (some VLC versions)
            track_elements = root.findall('.//track')
        
        for track_elem in track_elements:
            track_info = {
                'location': None,
                'title': None,
                'start_time': None
            }
            
            # Get location
            location = track_elem.find('xspf:location', namespaces)
            if location is None:
                location = track_elem.find('location')
            if location is not None and location.text:
                track_info['location'] = location.text
            
            # Get title
            title = track_elem.find('xspf:title', namespaces)
            if title is None:
                title = track_elem.find('title')
            if title is not None and title.text:
                track_info['title'] = title.text
            
            # Get start time from VLC extension
            # VLC stores it as: <extension application="..."><vlc:option>start-time=15</vlc:option></extension>
            extensions = track_elem.findall('.//xspf:extension', namespaces)
            if not extensions:
                extensions = track_elem.findall('.//extension')
            
            for ext in extensions:
                # Look for vlc:option elements
                options = ext.findall('.//vlc:option', namespaces)
                if not options:
                    options = ext.findall('.//option')
                
                for option in options:
                    if option.text and 'start-time=' in option.text:
                        try:
                            # Extract start-time value
                            start_time_str = option.text.split('start-time=')[1].strip()
                            # Handle potential spaces or extra characters
                            start_time_str = start_time_str.split()[0] if ' ' in start_time_str else start_time_str
                            track_info['start_time'] = float(start_time_str)
                            break
                        except (ValueError, IndexError) as e:
                            logger.warning(f"Failed to parse start-time from: {option.text} - {e}")
                
                if track_info['start_time'] is not None:
                    break
            
            tracks.append(track_info)
        
        return tracks
        
    except ET.ParseError as e:
        logger.error(f"XML parse error: {e}")
        return []
    except Exception as e:
        logger.error(f"Error parsing XSPF: {e}", exc_info=True)
        return []


def extract_filename_from_location(location: str) -> str:
    """
    Extract filename from a location string (handles file://, absolute paths, etc.)
    
    Args:
        location: Location string from XSPF
        
    Returns:
        Filename only
    """
    if not location:
        return ""
    
    # Remove file:// protocol if present
    if location.startswith('file://'):
        location = location[7:]
    
    # Get just the filename
    return Path(location).name


def verify_prepare_presentation_clips(traj, env_info, task_info):
    """
    Verify that presentation playlist was created correctly.
    
    Checks:
    1. Playlist file exists and is valid XSPF
    2. Contains exactly 3 videos in correct order
    3. Each video has correct start-time parameter
    
    Returns:
        Dict with 'passed' (bool), 'score' (float 0-100), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            'passed': False,
            'score': 0,
            'feedback': "❌ Copy function not available"
        }
    
    # Expected configuration
    expected_videos = [
        {"filename": "animal_foraging.mp4", "start_time": 15.0},
        {"filename": "colony_interaction.mp4", "start_time": 90.0},
        {"filename": "migration_pattern.mp4", "start_time": 45.0}
    ]
    tolerance = 2.0  # ±2 seconds tolerance
    
    playlist_path = "/tmp/vlc_presentation_playlist.xspf"
    
    # Create temp directory for copying files
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_presentation_')
    local_playlist = Path(temp_dir) / "talk_clips.xspf"
    
    try:
        # Step 1: Copy playlist file from container
        try:
            copy_from_env(playlist_path, str(local_playlist))
        except Exception as e:
            logger.error(f"Failed to copy playlist: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                'passed': False,
                'score': 0,
                'feedback': f"❌ Playlist file not found at {playlist_path}. Did you create and save the playlist?"
            }
        
        # Check file exists and has content
        if not local_playlist.exists() or local_playlist.stat().st_size == 0:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                'passed': False,
                'score': 0,
                'feedback': "❌ Playlist file is empty."
            }
        
        logger.info(f"Playlist file size: {local_playlist.stat().st_size} bytes")
        
        # Step 2: Parse XSPF playlist
        try:
            tracks = parse_xspf_with_start_times(str(local_playlist))
        except Exception as e:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                'passed': False,
                'score': 10,
                'feedback': f"❌ Playlist is not valid XSPF format: {e}. Make sure to save as XSPF, not M3U."
            }
        
        if not tracks:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                'passed': False,
                'score': 10,
                'feedback': "❌ Playlist is empty or has no tracks. Did you add the videos?"
            }
        
        # Step 3: Check track count
        if len(tracks) != 3:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                'passed': False,
                'score': 20,
                'feedback': f"❌ Expected 3 videos in playlist, found {len(tracks)}. Make sure to add all three videos."
            }
        
        # Step 4: Verify each track
        feedback_parts = []
        score_components = []
        all_correct = True
        
        for i, (track, expected) in enumerate(zip(tracks, expected_videos), 1):
            track_feedback = []
            track_score = 0.0
            max_track_score = 2.0  # Each track can contribute 2 points (1 for file, 1 for time)
            
            # Check location/file path
            location = track.get('location', '')
            filename = extract_filename_from_location(location)
            
            if not location:
                track_feedback.append(f"❌ Video {i}: Missing file path")
                all_correct = False
            elif expected['filename'] in filename:
                track_feedback.append(f"✓ Video {i}: Correct file ({expected['filename']})")
                track_score += 1.0
            else:
                track_feedback.append(f"❌ Video {i}: Wrong file (expected {expected['filename']}, got {filename})")
                all_correct = False
            
            # Check start time
            start_time = track.get('start_time')
            expected_start = expected['start_time']
            
            if start_time is None:
                track_feedback.append(f"   ❌ No start-time parameter found for video {i}")
                all_correct = False
            else:
                if abs(start_time - expected_start) <= tolerance:
                    track_feedback.append(f"   ✓ Correct start time: {start_time}s (expected {expected_start}s)")
                    track_score += 1.0
                else:
                    track_feedback.append(f"   ❌ Wrong start time: {start_time}s (expected {expected_start}s ±{tolerance}s)")
                    all_correct = False
            
            feedback_parts.extend(track_feedback)
            score_components.append(track_score / max_track_score)
        
        # Calculate final score
        # Base score from tracks (60% weight)
        tracks_score = sum(score_components) / len(score_components) if score_components else 0
        
        # Bonus for having all correct (40% weight)
        completeness_score = 1.0 if all_correct else 0.5
        
        final_score = (tracks_score * 0.6 + completeness_score * 0.4) * 100
        final_score = min(100, max(0, final_score))
        
        # Determine pass/fail (need at least 80%)
        passed = final_score >= 80
        
        # Compile feedback
        if passed:
            feedback_header = "✅ **Presentation playlist created successfully!**\n"
        else:
            feedback_header = "❌ **Playlist has issues:**\n"
        
        feedback = feedback_header + "\n".join(feedback_parts)
        
        if not passed:
            feedback += "\n\n💡 **Hint**: Use VLC's 'Media → Open File (Advanced)' to add files with start times. "
            feedback += "Check 'Show more options' and set 'Start time' before adding each video. "
            feedback += "Then save playlist as XSPF format (not M3U)."
        
        shutil.rmtree(temp_dir, ignore_errors=True)
        
        return {
            'passed': passed,
            'score': int(final_score),
            'feedback': feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            'passed': False,
            'score': 0,
            'feedback': f"❌ Verification error: {str(e)}"
        }
