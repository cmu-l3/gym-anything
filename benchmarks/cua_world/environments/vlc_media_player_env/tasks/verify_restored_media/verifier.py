#!/usr/bin/env python3
"""
Verifier for Verify Restored Media task

This verifier checks that the agent systematically verified all media files
from a restored backup directory by:
1. Parsing VLC's recently played history
2. Comparing against the list of media files in the backup directory
3. Ensuring all files were accessed during the task
"""

import sys
import os
import logging
import tempfile
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_xspf_history(xspf_path):
    """
    Parse VLC's XSPF media library file to extract recently played files.
    
    Args:
        xspf_path: Path to ml.xspf file
        
    Returns:
        Set of file paths that were played
    """
    played_files = set()
    
    try:
        if not os.path.exists(xspf_path) or os.path.getsize(xspf_path) == 0:
            logger.warning(f"XSPF file not found or empty: {xspf_path}")
            return played_files
        
        tree = ET.parse(xspf_path)
        root = tree.getroot()
        
        # XSPF namespace
        ns = {'xspf': 'http://xspf.org/ns/0/'}
        
        # Find all track locations
        for track in root.findall('.//xspf:track', ns):
            location = track.find('xspf:location', ns)
            if location is not None and location.text:
                # Parse file URI (e.g., file:///home/ga/Videos/...)
                uri = location.text
                if uri.startswith('file://'):
                    # Decode URI and extract path
                    file_path = unquote(urlparse(uri).path)
                    played_files.add(file_path)
                    logger.info(f"Found in XSPF: {file_path}")
        
        logger.info(f"Parsed {len(played_files)} files from XSPF")
        
    except Exception as e:
        logger.error(f"Error parsing XSPF: {e}")
    
    return played_files


def parse_vlc_qt_config(config_path):
    """
    Parse VLC Qt interface config for recent MRL list.
    
    Args:
        config_path: Path to vlc-qt-interface.conf
        
    Returns:
        Set of file paths from recent MRLs
    """
    played_files = set()
    
    try:
        if not os.path.exists(config_path) or os.path.getsize(config_path) == 0:
            logger.warning(f"Qt config not found or empty: {config_path}")
            return played_files
        
        with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
            in_recent_section = False
            for line in f:
                line = line.strip()
                
                if line.startswith('[RecentsMRL]'):
                    in_recent_section = True
                    continue
                elif line.startswith('[') and in_recent_section:
                    # End of RecentsMRL section
                    break
                
                if in_recent_section and '=' in line:
                    # Format: list=file:///path/to/file.mp4, ...
                    key, value = line.split('=', 1)
                    if 'list' in key.lower():
                        # Parse comma-separated MRLs
                        mrls = value.split(',')
                        for mrl in mrls:
                            mrl = mrl.strip().strip('"')
                            if mrl.startswith('file://'):
                                file_path = unquote(urlparse(mrl).path)
                                played_files.add(file_path)
                                logger.info(f"Found in Qt config: {file_path}")
        
        logger.info(f"Parsed {len(played_files)} files from Qt config")
        
    except Exception as e:
        logger.error(f"Error parsing Qt config: {e}")
    
    return played_files


def parse_recently_used_xbel(xbel_path):
    """
    Parse GTK recently-used.xbel file for VLC-opened files.
    
    Args:
        xbel_path: Path to recently-used.xbel
        
    Returns:
        Set of file paths opened by VLC
    """
    played_files = set()
    
    try:
        if not os.path.exists(xbel_path) or os.path.getsize(xbel_path) == 0:
            return played_files
        
        tree = ET.parse(xbel_path)
        root = tree.getroot()
        
        # Find bookmarks with VLC application
        for bookmark in root.findall('.//bookmark'):
            href = bookmark.get('href', '')
            
            # Check if opened by VLC
            applications = bookmark.find('.//applications')
            if applications is not None:
                for app in applications.findall('.//application'):
                    app_name = app.get('name', '')
                    if 'vlc' in app_name.lower():
                        if href.startswith('file://'):
                            file_path = unquote(urlparse(href).path)
                            played_files.add(file_path)
                            logger.info(f"Found in recently-used: {file_path}")
                        break
        
        logger.info(f"Parsed {len(played_files)} files from recently-used")
        
    except Exception as e:
        logger.error(f"Error parsing recently-used: {e}")
    
    return played_files


def get_expected_media_files(backup_info_path):
    """
    Get list of expected media files from backup directory info.
    
    Args:
        backup_info_path: Path to backup_directory_info.json
        
    Returns:
        Set of expected file paths
    """
    expected_files = set()
    
    try:
        with open(backup_info_path, 'r') as f:
            info = json.load(f)
        
        for file_info in info.get('files', []):
            file_path = file_info.get('path', '')
            if file_path:
                expected_files.add(file_path)
        
        logger.info(f"Expected {len(expected_files)} files to be verified")
        
    except Exception as e:
        logger.error(f"Error reading backup info: {e}")
    
    return expected_files


def verify_restored_media(traj, env_info, task_info):
    """
    Verify that all media files from restored backup were systematically checked.
    
    Checks:
    1. VLC history files are accessible
    2. All expected media files appear in VLC history
    3. Verification coverage is complete
    
    Scoring:
    - 100%: All files verified (100% coverage)
    - 85-99%: All files verified but with minor issues
    - 70-84%: Most files verified (90-99% coverage)
    - 50-69%: Significant gaps (70-89% coverage)
    - 0-49%: Failed to verify majority (<70% coverage)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Create temp directory for copied files
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_backup_')
    
    try:
        # Copy VLC history files
        xspf_temp = os.path.join(temp_dir, 'ml.xspf')
        qt_config_temp = os.path.join(temp_dir, 'vlc-qt-interface.conf')
        recently_used_temp = os.path.join(temp_dir, 'recently-used.xbel')
        backup_info_temp = os.path.join(temp_dir, 'backup_directory_info.json')
        
        try:
            copy_from_env("/tmp/vlc_history_ml.xspf", xspf_temp)
            copy_from_env("/tmp/vlc_history_qt.conf", qt_config_temp)
            copy_from_env("/tmp/vlc_recently_used.xbel", recently_used_temp)
            copy_from_env("/tmp/backup_directory_info.json", backup_info_temp)
        except Exception as e:
            logger.error(f"Error copying history files: {e}")
            return {"passed": False, "score": 0, "feedback": f"Failed to copy history files: {str(e)}"}
        
        criteria_met += 1
        feedback_parts.append("✅ VLC history accessible")
        
        # Parse VLC history from all sources
        played_files = set()
        played_files.update(parse_vlc_xspf_history(xspf_temp))
        played_files.update(parse_vlc_qt_config(qt_config_temp))
        played_files.update(parse_recently_used_xbel(recently_used_temp))
        
        # Get expected files
        expected_files = get_expected_media_files(backup_info_temp)
        
        if not expected_files:
            return {"passed": False, "score": 0, "feedback": "No expected files found in backup directory"}
        
        # Match files by basename (to handle path variations)
        expected_basenames = {os.path.basename(f): f for f in expected_files}
        played_basenames = {os.path.basename(f): f for f in played_files if 'restored_backup' in f}
        
        # Calculate coverage
        verified_files = set()
        missing_files = []
        
        for expected_basename, expected_path in expected_basenames.items():
            if expected_basename in played_basenames:
                verified_files.add(expected_basename)
            else:
                missing_files.append(expected_basename)
        
        verified_count = len(verified_files)
        expected_count = len(expected_basenames)
        coverage_percent = (verified_count / expected_count * 100) if expected_count > 0 else 0
        
        feedback_parts.append(f"Files verified: {verified_count}/{expected_count} ({coverage_percent:.1f}%)")
        
        # Criterion 2: Check coverage percentage
        if coverage_percent >= 100:
            criteria_met += 2  # Full marks for complete coverage
            feedback_parts.append(f"✅ All files verified ({verified_count}/{expected_count})")
        elif coverage_percent >= 90:
            criteria_met += 1.5
            feedback_parts.append(f"⚠️ Most files verified ({verified_count}/{expected_count})")
        elif coverage_percent >= 70:
            criteria_met += 1
            feedback_parts.append(f"⚠️ Some files verified ({verified_count}/{expected_count})")
        else:
            feedback_parts.append(f"❌ Insufficient coverage ({verified_count}/{expected_count})")
        
        # Add details about missing files
        if missing_files:
            if len(missing_files) <= 3:
                feedback_parts.append(f"Missing: {', '.join(missing_files)}")
            else:
                feedback_parts.append(f"Missing: {', '.join(missing_files[:3])} and {len(missing_files)-3} more")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup temp directory
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)
    
    # Calculate final score based on coverage
    # Scale: 100% coverage = 100 score, 90% = 85, 80% = 70, 70% = 55, etc.
    if coverage_percent >= 100:
        score = 100
    elif coverage_percent >= 90:
        score = 85 + int((coverage_percent - 90) * 1.5)
    elif coverage_percent >= 70:
        score = 70 + int((coverage_percent - 70) * 0.75)
    else:
        score = int(coverage_percent)
    
    passed = score >= 85
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "verified_count": verified_count,
            "expected_count": expected_count,
            "coverage_percent": coverage_percent,
            "missing_files": missing_files
        }
    }