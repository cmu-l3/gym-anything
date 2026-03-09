#!/usr/bin/env python3
"""
Verifier for Create Practice Segment Playlist task (create_practice_segment_playlist@1)

Validates that the playlist correctly references video segments with time ranges.
"""

import sys
import os
import logging
import tempfile
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_xspf_playlist_with_times(filepath: str) -> List[Dict[str, Any]]:
    """
    Parse XSPF playlist and extract time information.
    
    Returns list of dicts with: location, start_time, duration
    """
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # XSPF namespace
        ns = {'xspf': 'http://xspf.org/ns/0/'}
        
        entries = []
        for track in root.findall('.//xspf:track', ns):
            entry = {}
            
            # Get location
            location = track.find('xspf:location', ns)
            if location is not None:
                entry['location'] = location.text
            
            # Look for VLC extensions for start/stop time
            # VLC may use custom namespace for options
            vlc_ns = {'vlc': 'http://www.videolan.org/vlc/playlist/ns/0/'}
            
            for option in track.findall('.//vlc:option', vlc_ns):
                option_text = option.text or ""
                if 'start-time' in option_text:
                    try:
                        entry['start_time'] = float(option_text.split('=')[1])
                    except:
                        pass
                if 'stop-time' in option_text:
                    try:
                        stop_time = float(option_text.split('=')[1])
                        if 'start_time' in entry:
                            entry['duration'] = stop_time - entry['start_time']
                    except:
                        pass
            
            # Check for duration in standard XSPF format (milliseconds)
            duration_elem = track.find('xspf:duration', ns)
            if duration_elem is not None and 'duration' not in entry:
                try:
                    entry['duration'] = int(duration_elem.text) / 1000.0
                except:
                    pass
            
            entries.append(entry)
        
        return entries
        
    except Exception as e:
        logger.error(f"Error parsing XSPF playlist: {e}")
        return []


def parse_m3u_playlist_with_options(filepath: str) -> List[Dict[str, Any]]:
    """
    Parse M3U/M3U8 playlist and extract VLC-specific time options.
    
    Returns list of dicts with: location, start_time, duration
    """
    try:
        entries = []
        current_entry = {}
        
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                
                # Skip empty lines and comments (except directives)
                if not line:
                    continue
                
                # Parse VLC-specific options
                if line.startswith('#EXTVLCOPT:'):
                    option = line.replace('#EXTVLCOPT:', '')
                    
                    if 'start-time' in option:
                        try:
                            current_entry['start_time'] = float(option.split('=')[1])
                        except:
                            pass
                    
                    if 'stop-time' in option:
                        try:
                            stop_time = float(option.split('=')[1])
                            if 'start_time' in current_entry:
                                current_entry['duration'] = stop_time - current_entry['start_time']
                        except:
                            pass
                
                # Parse standard M3U duration
                elif line.startswith('#EXTINF:'):
                    try:
                        # Format: #EXTINF:duration,title
                        parts = line.replace('#EXTINF:', '').split(',', 1)
                        if 'duration' not in current_entry:
                            current_entry['duration'] = float(parts[0])
                    except:
                        pass
                
                # Non-comment line is a file path
                elif not line.startswith('#'):
                    current_entry['location'] = line
                    entries.append(current_entry)
                    current_entry = {}
        
        return entries
        
    except Exception as e:
        logger.error(f"Error parsing M3U playlist: {e}")
        return []


def check_playlist_loop_enabled(filepath: str, format_ext: str) -> bool:
    """
    Check if playlist has loop/repeat enabled.
    
    For M3U: Look for VLC loop options
    For XSPF: Look for extension attributes
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check for loop/repeat keywords
        if 'loop' in content.lower() or 'repeat' in content.lower():
            return True
        
        return False
        
    except:
        return False


def verify_task(traj, env_info, task_info):
    """
    Verify the practice segment playlist task.
    
    Checks:
    1. Playlist file exists in correct location
    2. Contains exactly 4 entries in correct order
    3. Each entry references the correct source video
    4. Time ranges are specified (XSPF) or options present (M3U)
    5. Time ranges match requirements (within 5 second tolerance)
    6. Total duration approximately 205 seconds (±15s)
    7. Loop/repeat setting (bonus)
    
    Returns:
        dict with 'passed', 'score', 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    score = 0.0
    
    # Expected segments: (filename, start_sec, end_sec, name)
    expected_segments = [
        ("tutorial_01_basics.mp4", 135, 165, "body isolation"),      # 2:15-2:45 = 30s
        ("tutorial_02_intermediate.mp4", 270, 300, "footwork"),      # 4:30-5:00 = 30s
        ("tutorial_03_arms.mp4", 60, 100, "arm movements"),          # 1:00-1:40 = 40s
        ("tutorial_04_cooldown.mp4", 480, 570, "stretching"),        # 8:00-9:30 = 90s
    ]
    expected_total_duration = 190  # 30+30+40+90 = 190s actual
    
    # Copy playlist metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_practice_playlist_meta.json", temp_meta.name)
        
        with open(temp_meta.name, 'r') as f:
            meta = json.load(f)
        
        if not meta.get('found', False):
            os.unlink(temp_meta.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ No playlist file found (looked for practice_sequence.xspf/m3u8/m3u)"
            }
        
        playlist_format = meta.get('format', '')
        feedback_parts.append(f"✓ Found playlist file: practice_sequence{playlist_format}")
        score += 0.15
        
        os.unlink(temp_meta.name)
        
    except Exception as e:
        logger.error(f"Error reading playlist metadata: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read playlist metadata: {str(e)}"
        }
    
    # Copy and parse playlist content
    temp_playlist = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_practice_playlist.txt", temp_playlist.name)
        
        # Detect format and parse
        entries = []
        
        if playlist_format in ['.xspf']:
            entries = parse_xspf_playlist_with_times(temp_playlist.name)
        elif playlist_format in ['.m3u', '.m3u8']:
            entries = parse_m3u_playlist_with_options(temp_playlist.name)
        else:
            # Try to auto-detect
            with open(temp_playlist.name, 'r') as f:
                first_line = f.readline().strip()
            
            if first_line.startswith('<?xml') or first_line.startswith('<'):
                entries = parse_xspf_playlist_with_times(temp_playlist.name)
            else:
                entries = parse_m3u_playlist_with_options(temp_playlist.name)
        
        if not entries:
            os.unlink(temp_playlist.name)
            return {
                "passed": False,
                "score": int(score * 100),
                "feedback": "❌ Playlist is empty or malformed"
            }
        
        feedback_parts.append(f"✓ Successfully parsed playlist ({len(entries)} entries)")
        score += 0.10
        
        # Check entry count
        if len(entries) != 4:
            feedback_parts.append(f"⚠ Expected 4 entries, found {len(entries)}")
            score += 0.05  # Partial credit
        else:
            feedback_parts.append("✓ Correct number of entries (4)")
            score += 0.15
        
        # Verify each segment
        segments_correct = 0.0
        total_actual_duration = 0
        
        for i, (expected_file, expected_start, expected_end, name) in enumerate(expected_segments):
            if i >= len(entries):
                feedback_parts.append(f"✗ Missing segment {i+1}: {name}")
                continue
            
            entry = entries[i]
            entry_location = entry.get('location', '')
            entry_start = entry.get('start_time', None)
            entry_duration = entry.get('duration', None)
            
            # Check if correct file is referenced
            if expected_file not in entry_location:
                feedback_parts.append(
                    f"✗ Segment {i+1}: Wrong video (expected {expected_file}, "
                    f"got {Path(entry_location).name if entry_location else 'none'})"
                )
                continue
            
            # Check if time information is present
            if entry_start is None and entry_duration is None:
                feedback_parts.append(f"⚠ Segment {i+1} ({name}): No time range specified")
                score += 0.025  # Minimal credit for having the file
                continue
            
            # Validate time ranges (with tolerance)
            expected_duration = expected_end - expected_start
            
            start_diff = abs(entry_start - expected_start) if entry_start is not None else 999
            duration_diff = abs(entry_duration - expected_duration) if entry_duration is not None else 999
            
            if entry_start is not None:
                if start_diff <= 5:  # 5 second tolerance
                    segments_correct += 0.25
                else:
                    feedback_parts.append(
                        f"⚠ Segment {i+1} ({name}): Start time off by {start_diff:.1f}s "
                        f"(expected {expected_start}s, got {entry_start}s)"
                    )
            
            if entry_duration is not None:
                if duration_diff <= 5:
                    segments_correct += 0.25
                else:
                    feedback_parts.append(
                        f"⚠ Segment {i+1} ({name}): Duration off by {duration_diff:.1f}s "
                        f"(expected {expected_duration}s, got {entry_duration}s)"
                    )
            
            # Calculate actual duration for this segment
            actual_duration = entry_duration if entry_duration is not None else expected_duration
            total_actual_duration += actual_duration
            
            # If both start and duration are correct
            if entry_start is not None and entry_duration is not None:
                if start_diff <= 5 and duration_diff <= 5:
                    feedback_parts.append(
                        f"✓ Segment {i+1} ({name}): Correct time range "
                        f"({int(entry_start)}s for {int(entry_duration)}s)"
                    )
                    segments_correct += 0.5
        
        # Award points for correct segments (max 0.40 points for 4 segments)
        score += segments_correct * 0.10
        
        # Check total duration
        duration_diff = abs(total_actual_duration - expected_total_duration)
        if duration_diff <= 15:  # Allow 15 second tolerance for total
            feedback_parts.append(
                f"✓ Total duration appropriate: {total_actual_duration}s "
                f"(expected ~{expected_total_duration}s)"
            )
            score += 0.15
        else:
            feedback_parts.append(
                f"⚠ Total duration off: {total_actual_duration}s "
                f"(expected ~{expected_total_duration}s, diff: {duration_diff}s)"
            )
            score += 0.05
        
        # Check for loop/repeat setting (bonus points)
        if check_playlist_loop_enabled(temp_playlist.name, playlist_format):
            feedback_parts.append("✓ Playlist configured to loop/repeat")
            score += 0.10
        else:
            feedback_parts.append("ℹ Playlist not set to loop (optional)")
        
        os.unlink(temp_playlist.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": int(score * 100),
            "feedback": f"Error parsing playlist: {str(e)}"
        }
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_practice_playlist_completed.txt", temp_marker.name)
        feedback_parts.append("✓ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠ Completion marker not found")
    
    # Determine success
    # Need: playlist exists, 4 entries, at least 3 segments mostly correct, reasonable duration
    success = (
        len(entries) == 4 and
        segments_correct >= 3.0 and  # At least 3 segments mostly correct
        duration_diff <= 30
    )
    
    # Convert score to percentage
    final_score = min(int(score * 100), 100)
    passed = success and final_score >= 70
    
    final_feedback = "\n".join(feedback_parts)
    
    if passed:
        final_feedback = f"✅ PASS - Practice sequence playlist created successfully!\n\n{final_feedback}"
    else:
        final_feedback = f"❌ INCOMPLETE - Playlist has issues\n\n{final_feedback}"
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": final_feedback
    }