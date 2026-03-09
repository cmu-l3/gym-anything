#!/usr/bin/env python3
"""
Verifier for Bookmark Interview Moments task
"""

import sys
import os
import logging
import tempfile
import json
import xml.etree.ElementTree as ET
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_xspf_playlist,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_bookmarks_from_xspf(filepath):
    """
    Parse bookmarks from XSPF file.
    
    Returns list of dicts with bookmark info: {name, time, location}
    """
    bookmarks = []
    
    try:
        tree = ET.parse(filepath)
        root = tree.getroot()
        
        # XSPF namespace
        ns = {'xspf': 'http://xspf.org/ns/0/'}
        
        # Find all tracks (potential bookmarks)
        for track in root.findall('.//xspf:track', ns):
            bookmark = {}
            
            # Get title/name
            title = track.find('xspf:title', ns)
            if title is not None and title.text:
                bookmark['name'] = title.text.lower()
            
            # Get location (file path)
            location = track.find('xspf:location', ns)
            if location is not None and location.text:
                bookmark['location'] = location.text
            
            # Get duration (in milliseconds)
            duration = track.find('xspf:duration', ns)
            if duration is not None and duration.text:
                try:
                    bookmark['time'] = int(duration.text) / 1000.0  # Convert ms to seconds
                except (ValueError, TypeError):
                    pass
            
            # Look for extension nodes that might contain bookmark timestamp
            extensions = track.findall('.//xspf:extension', ns)
            for ext in extensions:
                # Check for bookmark-specific extensions
                if 'bookmark' in str(ET.tostring(ext)).lower():
                    # Try to extract timestamp
                    for child in ext:
                        if 'time' in child.tag.lower() or 'position' in child.tag.lower():
                            try:
                                bookmark['time'] = float(child.text)
                            except (ValueError, TypeError):
                                pass
            
            # VLC sometimes stores bookmarks with specific metadata
            # Check for annotation/meta elements
            annotations = track.findall('.//xspf:annotation', ns)
            for ann in annotations:
                if ann.text and 'bookmark' in ann.text.lower():
                    bookmark['is_bookmark'] = True
            
            if bookmark:  # Only add if we got some data
                bookmarks.append(bookmark)
        
        logger.info(f"Parsed {len(bookmarks)} potential bookmarks from {filepath}")
        
    except Exception as e:
        logger.error(f"Error parsing XSPF file {filepath}: {e}")
    
    return bookmarks


def check_bookmark_timestamp(bookmark_time, expected_time, tolerance=5.0):
    """Check if bookmark timestamp matches expected time within tolerance."""
    if bookmark_time is None:
        return False
    return abs(bookmark_time - expected_time) <= tolerance


def check_bookmark_name(bookmark_name, expected_keywords):
    """Check if bookmark name contains any of the expected keywords."""
    if not bookmark_name:
        return False
    
    name_lower = bookmark_name.lower()
    return any(keyword in name_lower for keyword in expected_keywords)


def verify_bookmark_interview_moments(traj, env_info, task_info):
    """
    Verify bookmark interview moments task completion.
    
    Checks:
    1. Bookmark file(s) exist and are parseable
    2. Three bookmarks are present
    3. Bookmark timestamps match expected times (±5 seconds)
    4. Bookmark names contain relevant keywords
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 4
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp(prefix='vlc_bookmark_verify_')
    
    try:
        # Expected bookmarks
        EXPECTED_BOOKMARKS = [
            {
                "name_keywords": ["arrival", "first", "initial", "arriving", "day"],
                "time": 135,  # 2:15
                "tolerance": 5,
                "label": "Arrival Experience"
            },
            {
                "name_keywords": ["housing", "apartment", "discrimination", "challenge", "search", "difficult"],
                "time": 340,  # 5:40
                "tolerance": 5,
                "label": "Housing Challenges"
            },
            {
                "name_keywords": ["community", "support", "integration", "neighbor", "finding"],
                "time": 560,  # 9:20
                "tolerance": 5,
                "label": "Community Integration"
            }
        ]
        
        # Try to copy bookmark files
        bookmark_files_found = []
        
        # Check multiple potential bookmark file locations
        potential_files = [
            "/tmp/vlc_bookmark_ml.xspf",
            "/tmp/vlc_bookmark_bookmarks.xspf",
            "/tmp/vlc_bookmark_interview_migration_2024.mp4.xspf",
        ]
        
        for container_file in potential_files:
            try:
                host_file = os.path.join(temp_dir, os.path.basename(container_file))
                copy_from_env(container_file, host_file)
                
                if os.path.exists(host_file) and os.path.getsize(host_file) > 0:
                    bookmark_files_found.append(host_file)
                    logger.info(f"Found bookmark file: {container_file}")
            except Exception as e:
                # File might not exist, that's okay
                logger.debug(f"Could not copy {container_file}: {e}")
                continue
        
        # Also check for any XSPF files that were copied
        try:
            result_json = os.path.join(temp_dir, 'result.json')
            copy_from_env("/tmp/vlc_bookmark_result.json", result_json)
            
            with open(result_json, 'r') as f:
                result_data = json.load(f)
                logger.info(f"Bookmark result: {result_data}")
        except Exception as e:
            logger.warning(f"Could not read bookmark result JSON: {e}")
        
        # Parse bookmarks from all found files
        all_bookmarks = []
        
        for bookmark_file in bookmark_files_found:
            try:
                bookmarks = parse_bookmarks_from_xspf(bookmark_file)
                all_bookmarks.extend(bookmarks)
                logger.info(f"Extracted {len(bookmarks)} bookmarks from {bookmark_file}")
            except Exception as e:
                logger.error(f"Error parsing bookmark file {bookmark_file}: {e}")
        
        # Criterion 1: At least one bookmark file found
        if bookmark_files_found:
            criteria_met += 1
            feedback_parts.append(f"✅ Bookmark file(s) found ({len(bookmark_files_found)} file(s))")
        else:
            feedback_parts.append("❌ No bookmark files found - check if bookmarks were created and saved")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Check bookmark count
        if len(all_bookmarks) >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Sufficient bookmarks ({len(all_bookmarks)} found, expected 3)")
        elif len(all_bookmarks) > 0:
            feedback_parts.append(f"⚠️ Insufficient bookmarks ({len(all_bookmarks)} found, expected 3)")
        else:
            feedback_parts.append("❌ No bookmarks found in files")
            return {
                "passed": False,
                "score": 25,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criteria 3 & 4: Check timestamps and names
        matched_bookmarks = 0
        timestamp_matches = 0
        name_matches = 0
        
        for expected in EXPECTED_BOOKMARKS:
            # Try to find a matching bookmark
            best_match = None
            best_score = 0
            
            for bookmark in all_bookmarks:
                match_score = 0
                
                # Check timestamp match
                if 'time' in bookmark:
                    if check_bookmark_timestamp(bookmark['time'], expected['time'], expected['tolerance']):
                        match_score += 2  # Timestamp is important
                
                # Check name match
                if 'name' in bookmark:
                    if check_bookmark_name(bookmark['name'], expected['name_keywords']):
                        match_score += 1  # Name is also important
                
                if match_score > best_score:
                    best_score = match_score
                    best_match = bookmark
            
            if best_match and best_score >= 2:
                # Good match (at least timestamp correct)
                matched_bookmarks += 1
                
                if 'time' in best_match and check_bookmark_timestamp(
                    best_match['time'], expected['time'], expected['tolerance']
                ):
                    timestamp_matches += 1
                
                if 'name' in best_match and check_bookmark_name(
                    best_match['name'], expected['name_keywords']
                ):
                    name_matches += 1
                
                feedback_parts.append(
                    f"✅ {expected['label']}: time={best_match.get('time', 'N/A'):.1f}s, "
                    f"name='{best_match.get('name', 'unnamed')}'"
                )
            elif best_match:
                # Partial match
                feedback_parts.append(
                    f"⚠️ {expected['label']}: partial match - "
                    f"time={best_match.get('time', 'N/A')}, name='{best_match.get('name', 'unnamed')}'"
                )
            else:
                feedback_parts.append(f"❌ {expected['label']}: no matching bookmark found")
        
        # Criterion 3: Timestamp accuracy
        if timestamp_matches >= 3:
            criteria_met += 1
        elif timestamp_matches >= 2:
            criteria_met += 0.5
        
        # Criterion 4: Name quality
        if name_matches >= 2:
            criteria_met += 1
        elif name_matches >= 1:
            criteria_met += 0.5
        
        # Clean up temp directory
        cleanup_verification_environment(temp_dir)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_environment(temp_dir)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }