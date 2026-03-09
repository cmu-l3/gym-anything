#!/usr/bin/env python3
"""
Verifier for Bookmark Video Positions task.

Checks if bookmarks were created at the correct timestamps.
"""

import os
import sys
import logging
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple, Set

# Add utils to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Expected bookmarks (name, timestamp in seconds, tolerance in seconds)
EXPECTED_BOOKMARKS = [
    ("Resume Point", 2120, 10),      # 35:20 ± 10s
    ("Mars Landing", 750, 10),        # 12:30 ± 10s
    ("Voyager Mission", 3480, 10),    # 58:00 ± 10s
    ("Conclusion", 4935, 10),         # 82:15 ± 10s
]


def parse_m3u_playlist(filepath: str) -> List[Dict[str, any]]:
    """
    Parse M3U playlist file looking for start-time options.
    
    Returns:
        List of dicts with 'location' and 'start_time' keys
    """
    items = []
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        current_item = {}
        
        for line in lines:
            line = line.strip()
            
            # Skip empty lines and #EXTM3U header
            if not line or line == '#EXTM3U':
                continue
            
            # Check for VLC options (start-time)
            if line.startswith('#EXTVLCOPT:'):
                option = line.replace('#EXTVLCOPT:', '')
                if 'start-time' in option.lower():
                    # Extract time value
                    match = re.search(r'start-time[=:]\s*(\d+)', option, re.IGNORECASE)
                    if match:
                        current_item['start_time'] = int(match.group(1))
            
            # Check for extended info
            elif line.startswith('#EXTINF:'):
                # Parse title if present
                if ',' in line:
                    title = line.split(',', 1)[1]
                    current_item['title'] = title
            
            # Check for comments that might contain time info
            elif line.startswith('#'):
                # Look for timestamps in comments
                time_match = re.search(r'(\d{1,2}):(\d{2})(?::(\d{2}))?', line)
                if time_match:
                    hours = 0
                    minutes = int(time_match.group(1))
                    seconds = int(time_match.group(2))
                    if time_match.group(3):
                        hours = minutes
                        minutes = seconds
                        seconds = int(time_match.group(3))
                    total_seconds = hours * 3600 + minutes * 60 + seconds
                    if 'start_time' not in current_item:
                        current_item['start_time_comment'] = total_seconds
            
            # File path
            elif not line.startswith('#'):
                current_item['location'] = line
                
                # Save current item if it has useful info
                if current_item:
                    items.append(current_item.copy())
                current_item = {}
        
    except Exception as e:
        logger.error(f"Error parsing M3U {filepath}: {e}")
    
    return items


def parse_xspf_playlist(filepath: str) -> List[Dict[str, any]]:
    """
    Parse XSPF playlist file looking for time markers.
    
    Returns:
        List of dicts with 'location', 'start_time', and other keys
    """
    items = []
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # XSPF namespace
        ns = {'xspf': 'http://xspf.org/ns/0/'}
        ns_vlc = {'vlc': 'http://www.videolan.org/vlc/playlist/ns/0/'}
        
        # Try both with and without namespace
        tracks = root.findall('.//xspf:track', ns)
        if not tracks:
            tracks = root.findall('.//track')
        
        for track in tracks:
            item = {}
            
            # Get location
            location = track.find('xspf:location', ns)
            if location is None:
                location = track.find('location')
            if location is not None and location.text:
                item['location'] = location.text
            
            # Get title
            title = track.find('xspf:title', ns)
            if title is None:
                title = track.find('title')
            if title is not None and title.text:
                item['title'] = title.text
            
            # Get duration
            duration = track.find('xspf:duration', ns)
            if duration is None:
                duration = track.find('duration')
            if duration is not None and duration.text:
                item['duration'] = int(duration.text) / 1000.0  # Convert ms to seconds
            
            # Look for VLC extensions
            extensions = track.findall('.//xspf:extension', ns)
            if not extensions:
                extensions = track.findall('.//extension')
            
            for extension in extensions:
                # Look for VLC options
                options = extension.findall('.//vlc:option', ns_vlc)
                if not options:
                    options = extension.findall('.//option')
                
                for option in options:
                    if option.text and 'start-time' in option.text.lower():
                        match = re.search(r'start-time[=:]\s*(\d+)', option.text, re.IGNORECASE)
                        if match:
                            item['start_time'] = int(match.group(1))
            
            # Look for start-time in attributes
            for attr, value in track.attrib.items():
                if 'start' in attr.lower() and value.isdigit():
                    item['start_time'] = int(value)
            
            if item:
                items.append(item)
        
    except Exception as e:
        logger.error(f"Error parsing XSPF {filepath}: {e}")
    
    return items


def extract_timestamps_from_file(filepath: str) -> Set[int]:
    """
    Extract all potential timestamp values from any file.
    Looks for various patterns that might indicate bookmarks.
    """
    timestamps = set()
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Pattern 1: start-time=XXXX
        for match in re.finditer(r'start[_-]?time[=:]\s*(\d+)', content, re.IGNORECASE):
            time_val = int(match.group(1))
            if 100 < time_val < 6000:  # Reasonable range for 90-min video
                timestamps.add(time_val)
        
        # Pattern 2: time=XXXX or position=XXXX
        for match in re.finditer(r'\b(?:time|position|seek)[=:]\s*(\d+)\b', content, re.IGNORECASE):
            time_val = int(match.group(1))
            if 100 < time_val < 6000:
                timestamps.add(time_val)
        
        # Pattern 3: MM:SS or HH:MM:SS timestamps
        for match in re.finditer(r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b', content):
            hours = 0
            minutes = int(match.group(1))
            seconds = int(match.group(2))
            if match.group(3):
                hours = minutes
                minutes = seconds
                seconds = int(match.group(3))
            total = hours * 3600 + minutes * 60 + seconds
            if 100 < total < 6000:
                timestamps.add(total)
        
        # Pattern 4: Standalone numbers that might be seconds
        # Only consider if near expected values
        for match in re.finditer(r'\b(\d{3,4})\b', content):
            time_val = int(match.group(1))
            # Check if close to any expected bookmark
            for _, expected_time, tolerance in EXPECTED_BOOKMARKS:
                if abs(time_val - expected_time) <= tolerance:
                    timestamps.add(time_val)
                    break
        
    except Exception as e:
        logger.debug(f"Error extracting timestamps from {filepath}: {e}")
    
    return timestamps


def search_for_bookmarks(export_dir: str) -> List[Tuple[str, int]]:
    """
    Search all files in export directory for bookmark-like entries.
    
    Returns:
        List of (source_file, timestamp) tuples
    """
    found_bookmarks = []
    
    if not os.path.exists(export_dir):
        logger.error(f"Export directory not found: {export_dir}")
        return found_bookmarks
    
    # Process each file in export directory
    for filename in os.listdir(export_dir):
        filepath = os.path.join(export_dir, filename)
        
        if not os.path.isfile(filepath):
            continue
        
        logger.info(f"Scanning file: {filename}")
        
        # Parse based on file type
        if filename.endswith('.m3u') or filename.endswith('.m3u8'):
            items = parse_m3u_playlist(filepath)
            for item in items:
                if 'start_time' in item:
                    found_bookmarks.append((filename, item['start_time']))
                    logger.info(f"  Found M3U bookmark: {item['start_time']}s")
                elif 'start_time_comment' in item:
                    found_bookmarks.append((filename, item['start_time_comment']))
                    logger.info(f"  Found M3U timestamp: {item['start_time_comment']}s")
        
        elif filename.endswith('.xspf'):
            items = parse_xspf_playlist(filepath)
            for item in items:
                if 'start_time' in item:
                    found_bookmarks.append((filename, item['start_time']))
                    logger.info(f"  Found XSPF bookmark: {item['start_time']}s")
        
        # For any file, also do generic timestamp extraction
        timestamps = extract_timestamps_from_file(filepath)
        for ts in timestamps:
            found_bookmarks.append((filename, ts))
            logger.debug(f"  Found timestamp: {ts}s")
    
    return found_bookmarks


def verify_bookmarks(export_dir: str) -> Tuple[bool, str, float]:
    """
    Main verification function.
    
    Returns:
        (success, feedback, score)
    """
    # Search for bookmarks
    found_bookmarks = search_for_bookmarks(export_dir)
    
    if not found_bookmarks:
        return False, (
            "❌ No bookmarks found in any files. "
            "Please create bookmarks using one of the suggested methods: "
            "(1) playlist with start-time options, (2) VLC's bookmark feature, "
            "or (3) media library entries."
        ), 0.0
    
    # Remove duplicates and sort
    unique_timestamps = sorted(set(ts for _, ts in found_bookmarks))
    
    logger.info(f"Found {len(unique_timestamps)} unique timestamp(s): {unique_timestamps}")
    
    # Match found timestamps to expected bookmarks
    matched = []
    missing = []
    
    for name, expected_time, tolerance in EXPECTED_BOOKMARKS:
        found = False
        for ts in unique_timestamps:
            if abs(ts - expected_time) <= tolerance:
                matched.append((name, expected_time, ts))
                found = True
                break
        
        if not found:
            missing.append((name, expected_time))
    
    # Calculate score
    score = len(matched) / len(EXPECTED_BOOKMARKS)
    
    # Generate feedback
    feedback_parts = []
    
    if matched:
        feedback_parts.append(f"✅ Found {len(matched)}/{len(EXPECTED_BOOKMARKS)} expected bookmarks:")
        for name, expected, actual in matched:
            diff = actual - expected
            feedback_parts.append(f"  • {name}: {actual}s (expected {expected}s, diff: {diff:+d}s)")
    
    if missing:
        feedback_parts.append(f"\n❌ Missing {len(missing)} bookmark(s):")
        for name, expected in missing:
            minutes = expected // 60
            seconds = expected % 60
            feedback_parts.append(f"  • {name}: {expected}s ({minutes}:{seconds:02d})")
    
    feedback_parts.append(f"\nTotal unique timestamps found: {len(unique_timestamps)}")
    
    if unique_timestamps:
        feedback_parts.append("Timestamps: " + ", ".join(f"{ts}s" for ts in unique_timestamps[:10]))
    
    feedback = "\n".join(feedback_parts)
    
    # Success if at least 3 out of 4 bookmarks found (75%)
    success = len(matched) >= 3
    
    if success:
        feedback = "✅ Task completed successfully!\n" + feedback
    elif matched:
        feedback = "⚠️ Partial success - some bookmarks found.\n" + feedback
    
    return success, feedback, score


def verify_task(traj, env_info, task_info):
    """
    Main entry point for task verification.
    Called by gym-anything framework.
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task info (unused)
    
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    export_dir = "/tmp/task_export"
    
    logger.info("=== Starting Bookmark Verification ===")
    
    success, feedback, score = verify_bookmarks(export_dir)
    
    # Convert score to percentage
    score_percent = int(score * 100)
    
    logger.info(f"Verification complete: success={success}, score={score_percent}%")
    
    return {
        "passed": success,
        "score": score_percent,
        "feedback": feedback
    }
