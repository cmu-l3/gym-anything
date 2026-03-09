#!/usr/bin/env python3
"""
Verifier for Resume Position Recovery task

Checks that:
1. VLC is configured to enable resume/continue playback
2. The documentary was played to approximately 47 minutes
3. Playback position was saved correctly in media library
4. Resume functionality would work when reopening VLC
"""

import json
import logging
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# Add utils to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def verify_resume_settings(vlcrc_path: str) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Verify VLC is configured to support resume playback.
    
    qt-continue values:
    - 0 = ask user (acceptable)
    - 1 = always resume (acceptable)
    - 2 = never resume (not acceptable - initial state)
    
    Returns:
        (success, feedback, details_dict)
    """
    if not os.path.exists(vlcrc_path):
        return False, "VLC configuration file not found", {}
    
    config = parse_vlc_config(vlcrc_path)
    
    # Check for resume/continue setting
    qt_continue = config.get('qt-continue', '2')  # Default is often 2 (never)
    qt_recentplay = config.get('qt-recentplay', '0')
    
    details = {
        'qt_continue': qt_continue,
        'qt_continue_raw': config.get('qt-continue', 'NOT_SET'),
        'qt_recentplay': qt_recentplay,
        'continue_enabled': qt_continue in ['0', '1']
    }
    
    # Check if resume is enabled
    if qt_continue == '2':
        return False, "Resume playback is DISABLED (qt-continue=2). Must be set to 0 (ask) or 1 (always).", details
    
    if qt_continue == '0':
        feedback = "✓ Resume playback enabled: ASK mode (qt-continue=0) - will prompt user to resume"
        return True, feedback, details
    elif qt_continue == '1':
        feedback = "✓ Resume playback enabled: ALWAYS mode (qt-continue=1) - will auto-resume"
        return True, feedback, details
    else:
        return False, f"Unexpected qt-continue value: '{qt_continue}'", details


def parse_time_to_seconds(time_str: str) -> float:
    """Convert various time formats to seconds."""
    if not time_str:
        return 0.0
    
    # Handle milliseconds (from XSPF duration tags)
    if time_str.isdigit():
        return float(time_str) / 1000.0
    
    # Handle HH:MM:SS or MM:SS or SS format
    parts = str(time_str).split(':')
    try:
        if len(parts) == 3:
            h, m, s = parts
            return int(h) * 3600 + int(m) * 60 + float(s)
        elif len(parts) == 2:
            m, s = parts
            return int(m) * 60 + float(s)
        else:
            return float(time_str)
    except (ValueError, TypeError):
        return 0.0


def verify_playback_position_xspf(ml_xspf_path: str) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Verify playback position from VLC's ml.xspf media library.
    
    XSPF format stores playback positions in extension elements.
    VLC 3.x stores current position for "resume where you left off" functionality.
    
    Returns:
        (success, feedback, details_dict)
    """
    if not os.path.exists(ml_xspf_path):
        return False, "Media library (ml.xspf) not found - video may not have been played", {}
    
    # Check if file is empty or just says "NOT_FOUND"
    with open(ml_xspf_path, 'r') as f:
        content = f.read()
        if 'NOT_FOUND' in content or len(content) < 50:
            return False, "Media library file is empty or invalid", {}
    
    try:
        tree = ET.parse(ml_xspf_path)
        root = tree.getroot()
        
        # XSPF namespace
        ns = {'xspf': 'http://xspf.org/ns/0/'}
        
        # Look for the documentary in the playlist
        target_file = 'documentary_urban_planning.mp4'
        found = False
        position_ms = 0
        duration_ms = 0
        
        for track in root.findall('.//xspf:track', ns):
            location = track.find('xspf:location', ns)
            if location is not None and target_file in location.text:
                found = True
                logger.info(f"Found documentary in media library: {location.text}")
                
                # Get duration
                duration_elem = track.find('xspf:duration', ns)
                if duration_elem is not None and duration_elem.text:
                    try:
                        duration_ms = int(duration_elem.text)
                    except (ValueError, TypeError):
                        pass
                
                # Check for VLC extension elements containing playback position
                # VLC stores position in various extension attributes
                for extension in track.findall('.//xspf:extension', ns):
                    # Look for vlc:item or other VLC-specific tags
                    for child in extension:
                        tag_lower = child.tag.lower()
                        
                        # Check for position/time attributes
                        if 'time' in tag_lower or 'position' in tag_lower or 'current' in tag_lower:
                            if child.text:
                                try:
                                    position_ms = int(child.text)
                                    logger.info(f"Found position in {child.tag}: {position_ms}ms")
                                    break
                                except (ValueError, TypeError):
                                    pass
                        
                        # Check element attributes
                        for attr_name, attr_value in child.attrib.items():
                            attr_lower = attr_name.lower()
                            if 'time' in attr_lower or 'position' in attr_lower:
                                try:
                                    position_ms = int(attr_value)
                                    logger.info(f"Found position in attribute {attr_name}: {position_ms}ms")
                                    break
                                except (ValueError, TypeError):
                                    pass
                
                break
        
        if not found:
            return False, f"Documentary '{target_file}' not found in media library - video may not have been opened", {}
        
        position_sec = position_ms / 1000.0
        position_min = position_sec / 60.0
        duration_sec = duration_ms / 1000.0
        
        # Target is 47 minutes ± 30 seconds
        target_sec = 47 * 60  # 2820 seconds
        target_min = 47.0
        tolerance_sec = 30
        
        details = {
            'position_ms': position_ms,
            'position_seconds': position_sec,
            'position_minutes': position_min,
            'position_formatted': f"{int(position_min)}:{int(position_sec % 60):02d}",
            'duration_seconds': duration_sec,
            'target_seconds': target_sec,
            'target_minutes': target_min,
            'tolerance_seconds': tolerance_sec,
            'found_in_library': True
        }
        
        # Check if position is in acceptable range
        if position_sec >= (target_sec - tolerance_sec) and position_sec <= (target_sec + tolerance_sec):
            return True, f"✓ Playback position saved at {position_min:.1f} min (target: {target_min}±0.5 min)", details
        elif position_sec > 60:
            # Position was changed but not to target
            return False, f"Position {position_min:.1f} min is outside target range ({target_min}±0.5 min)", details
        else:
            # Position is near start - likely not seeked
            return False, f"Position {position_min:.1f} min too early - video may not have been seeked to target", details
    
    except ET.ParseError as e:
        logger.error(f"Error parsing ml.xspf: {e}")
        return False, f"Media library file is corrupted or invalid XML", {}
    except Exception as e:
        logger.error(f"Error parsing ml.xspf: {e}")
        return False, f"Error parsing media library: {str(e)}", {}


def verify_playback_position_db(db_path: str) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Verify playback position from VLC's SQLite media library database.
    
    VLC 3.x stores media metadata and playback progress in SQLite database.
    Progress is stored as a float (0.0 to 1.0 representing percentage through video).
    
    Returns:
        (success, feedback, details_dict)
    """
    if not os.path.exists(db_path):
        return False, "Media library database not found", {}
    
    try:
        import sqlite3
        
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Query for the documentary
        target_file = 'documentary_urban_planning.mp4'
        
        # Try to find the media and its playback position
        # VLC database schema may vary by version, try multiple approaches
        try:
            cursor.execute("""
                SELECT mrl, progress, duration, play_count 
                FROM Media 
                WHERE mrl LIKE ?
            """, (f'%{target_file}%',))
            
            row = cursor.fetchone()
        except sqlite3.OperationalError:
            # Try alternative table/column names
            try:
                cursor.execute("""
                    SELECT mrl, progress, duration, nb_played 
                    FROM Media 
                    WHERE mrl LIKE ?
                """, (f'%{target_file}%',))
                row = cursor.fetchone()
            except:
                row = None
        
        conn.close()
        
        if not row:
            return False, f"Documentary not found in media database", {}
        
        mrl, progress, duration, play_count = row
        logger.info(f"Found in DB - MRL: {mrl}, Progress: {progress}, Duration: {duration}, Plays: {play_count}")
        
        # Calculate position from progress ratio and duration
        if duration and progress is not None:
            # Progress is typically 0.0-1.0 float
            position_sec = float(duration) * float(progress) / 1000.0  # duration might be in ms
            
            # If position seems wrong, try without ms conversion
            if position_sec > 10000:
                position_sec = float(duration) * float(progress)
            
            position_min = position_sec / 60.0
            
            target_sec = 47 * 60  # 2820 seconds
            target_min = 47.0
            tolerance_sec = 30
            
            details = {
                'position_seconds': position_sec,
                'position_minutes': position_min,
                'position_formatted': f"{int(position_min)}:{int(position_sec % 60):02d}",
                'progress_ratio': progress,
                'duration': duration,
                'play_count': play_count,
                'target_seconds': target_sec,
                'target_minutes': target_min,
                'found_in_database': True
            }
            
            if position_sec >= (target_sec - tolerance_sec) and position_sec <= (target_sec + tolerance_sec):
                return True, f"✓ Position saved at {position_min:.1f} min (progress: {float(progress)*100:.1f}%)", details
            elif position_sec > 60:
                return False, f"Position {position_min:.1f} min outside target {target_min}±0.5 min", details
            else:
                return False, f"Position {position_min:.1f} min too early - not seeked to target", details
        
        return False, "Playback position data incomplete in database", {
            'row': row,
            'found_in_database': True
        }
    
    except ImportError:
        logger.error("sqlite3 module not available")
        return False, "Cannot verify database (sqlite3 not available)", {}
    except Exception as e:
        logger.error(f"Error querying media database: {e}")
        return False, f"Database error: {str(e)}", {}


def verify_resume_position(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for resume_position_recovery task.
    
    Verifies:
    1. VLC resume settings configured correctly (qt-continue = 0 or 1)
    2. Documentary video was played and position saved
    3. Playback position is at target (~47 minutes ± 30 seconds)
    
    Args:
        traj: Trajectory data (not used in this verifier)
        env_info: Environment info including copy_from_env function
        task_info: Task metadata (not used in this verifier)
        
    Returns:
        Dict with verification results: passed, score, feedback, details
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }
    
    result = {
        'passed': False,
        'score': 0,
        'feedback': [],
        'details': {}
    }
    
    criteria_met = 0
    total_criteria = 3
    
    logger.info("=" * 70)
    logger.info("Verifying Resume Position Recovery Task")
    logger.info("=" * 70)
    
    # Create temp directory for copied files
    temp_dir = tempfile.mkdtemp(prefix='vlc_resume_verify_')
    
    try:
        # Copy all exported files
        vlcrc_path = os.path.join(temp_dir, 'vlcrc')
        ml_xspf_path = os.path.join(temp_dir, 'ml.xspf')
        db_path = os.path.join(temp_dir, 'vlc-media-library.db')
        
        # Copy vlcrc
        try:
            copy_from_env("/tmp/outputs/vlcrc", vlcrc_path)
        except Exception as e:
            logger.error(f"Failed to copy vlcrc: {e}")
        
        # Copy media library files
        try:
            copy_from_env("/tmp/outputs/ml.xspf", ml_xspf_path)
        except Exception as e:
            logger.warning(f"Failed to copy ml.xspf: {e}")
        
        try:
            copy_from_env("/tmp/outputs/vlc-media-library.db", db_path)
        except Exception as e:
            logger.warning(f"Failed to copy database: {e}")
        
        # Check 1: VLC resume settings configured
        logger.info("\n[1/3] Checking VLC resume settings...")
        settings_ok, settings_feedback, settings_details = verify_resume_settings(vlcrc_path)
        
        result['feedback'].append(settings_feedback)
        result['details']['resume_settings'] = settings_details
        
        if not settings_ok:
            logger.error(f"✗ {settings_feedback}")
            result['feedback'].append("FAILED: Resume playback not properly configured")
            result['score'] = 0
            return result
        
        logger.info(f"✓ {settings_feedback}")
        criteria_met += 1
        
        # Check 2 & 3: Playback position saved and at correct location
        logger.info("\n[2/3] Checking saved playback position...")
        
        position_verified = False
        position_feedback = ""
        position_details = {}
        
        # Try XSPF first (more commonly used for playback position)
        xspf_ok, xspf_feedback, xspf_details = verify_playback_position_xspf(ml_xspf_path)
        
        if xspf_ok:
            position_verified = True
            position_feedback = xspf_feedback
            position_details = xspf_details
            logger.info(f"✓ {xspf_feedback}")
            criteria_met += 2  # Both position saved AND correct
        elif xspf_details.get('found_in_library'):
            # Found in library but wrong position
            position_feedback = xspf_feedback
            position_details = xspf_details
            logger.warning(f"⚠ {xspf_feedback}")
            criteria_met += 1  # Partial credit for saving position
        else:
            logger.warning(f"XSPF check: {xspf_feedback}")
            
            # Try SQLite database as fallback
            logger.info("\n[3/3] Trying SQLite database...")
            db_ok, db_feedback, db_details = verify_playback_position_db(db_path)
            
            if db_ok:
                position_verified = True
                position_feedback = db_feedback
                position_details = db_details
                logger.info(f"✓ {db_feedback}")
                criteria_met += 2
            elif db_details.get('found_in_database'):
                position_feedback = db_feedback
                position_details = db_details
                logger.warning(f"⚠ {db_feedback}")
                criteria_met += 1
            else:
                logger.warning(f"Database check: {db_feedback}")
                position_feedback = "Video not found in media library - may not have been opened/played"
                result['details']['xspf_attempt'] = xspf_feedback
                result['details']['db_attempt'] = db_feedback
        
        result['feedback'].append(position_feedback)
        result['details']['playback_position'] = position_details
        
        # Calculate final score and result
        score = int((criteria_met / total_criteria) * 100)
        result['score'] = score
        result['passed'] = score >= 70
        
        # Generate final feedback
        logger.info("\n" + "=" * 70)
        if result['passed']:
            final_msg = f"✓ TASK COMPLETED: Resume configured and position saved at ~47 minutes (Score: {score}%)"
            result['feedback'].append(final_msg)
            logger.info(final_msg)
        else:
            final_msg = f"✗ TASK INCOMPLETE: Score {score}% (need 70%)"
            result['feedback'].append(final_msg)
            logger.error(final_msg)
            
            # Add helpful hints
            if criteria_met == 0:
                result['feedback'].append("Hint: Start by enabling resume in Tools → Preferences")
            elif criteria_met == 1:
                result['feedback'].append("Hint: Open the video and seek to 47:00, then close VLC with Ctrl+Q")
        
        logger.info("=" * 70)
    
    finally:
        # Cleanup temp directory
        import shutil
        try:
            shutil.rmtree(temp_dir)
        except Exception as e:
            logger.warning(f"Failed to cleanup temp dir: {e}")
    
    return result
