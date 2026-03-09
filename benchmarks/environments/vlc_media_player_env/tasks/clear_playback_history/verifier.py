#!/usr/bin/env python3
"""
Verifier for Clear Playback History task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_clear_playback_history(traj, env_info, task_info):
    """
    Verify clear playback history task completion.
    
    Checks:
    1. VLC config file accessible
    2. No recent-items entries in vlcrc
    3. Media Library has no track entries (or file is minimal/empty)
    
    Returns:
        dict: Result with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Use tempfile for all operations
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_ml = tempfile.NamedTemporaryFile(delete=False, suffix='.xspf', mode='w+')
    
    try:
        # Criterion 1: Copy and parse VLC config
        try:
            copy_from_env("/tmp/vlc_history_vlcrc.txt", temp_vlcrc.name)
            criteria_met += 1
            feedback_parts.append("✅ Config accessible")
        except Exception as e:
            logger.error(f"Error copying vlcrc: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Cannot access VLC config: {str(e)}"}
        
        # Criterion 2: Check for recent-items in vlcrc
        recent_items_found = False
        recent_items_count = 0
        file_references = []
        
        with open(temp_vlcrc.name, 'r', encoding='utf-8', errors='ignore') as f:
            vlcrc_content = f.read()
            
            # Look for recent-items lines
            for line in vlcrc_content.split('\n'):
                line_lower = line.lower()
                
                # Check for recent-items configuration
                if 'recent-items=' in line_lower or 'recent_items=' in line_lower:
                    # Extract the value after =
                    if '=' in line:
                        value = line.split('=', 1)[1].strip()
                        
                        # Check if value contains file references
                        if value and value != '0' and value != '':
                            # Look for file:// URIs or specific filenames
                            if 'file://' in value:
                                recent_items_found = True
                                # Count file references
                                file_refs = re.findall(r'file://[^\s,]+', value)
                                file_references.extend(file_refs)
                                
                            # Also check for the specific test files
                            if any(name in value for name in ['sample_video', 'color_test', 'sample_audio', 'video_personal']):
                                recent_items_found = True
                
                # Check for list-of-recent count
                if 'list-of-recent=' in line_lower:
                    if '=' in line:
                        count_str = line.split('=', 1)[1].strip()
                        if count_str.isdigit():
                            recent_items_count = int(count_str)
        
        # Evaluate recent-items criterion
        if recent_items_found:
            feedback_parts.append(f"❌ Recent files still in config: {len(file_references)} file(s) found")
            logger.info(f"File references found: {file_references[:3]}")  # Log first 3
        elif recent_items_count > 0:
            # Config says there are recent items but we didn't find file URIs
            # This might be partially cleared
            feedback_parts.append(f"⚠️ Recent count is {recent_items_count} but no file URIs found")
            criteria_met += 0.5
        else:
            criteria_met += 1
            feedback_parts.append("✅ Recent files cleared from config")
        
        # Criterion 3: Check Media Library
        try:
            copy_from_env("/tmp/vlc_history_ml.xspf", temp_ml.name)
            
            with open(temp_ml.name, 'r', encoding='utf-8', errors='ignore') as f:
                ml_content = f.read()
            
            # Count <track> entries
            track_count = ml_content.count('<track>')
            
            # Check for specific file references
            media_files_in_ml = []
            for filename in ['sample_video', 'color_test', 'sample_audio', 'video_personal']:
                if filename in ml_content:
                    media_files_in_ml.append(filename)
            
            if track_count == 0 and not media_files_in_ml:
                criteria_met += 1
                feedback_parts.append("✅ Media Library cleared (no tracks)")
            elif track_count > 0:
                feedback_parts.append(f"❌ Media Library still has {track_count} track(s)")
                logger.info(f"Files in ML: {media_files_in_ml[:3]}")
            else:
                # File might have structure but no actual tracks
                criteria_met += 1
                feedback_parts.append("✅ Media Library cleared")
                
        except Exception as e:
            # Media Library file not found - this could mean it was deleted, which is OK
            logger.info(f"Media Library file not found or empty: {e}")
            criteria_met += 1
            feedback_parts.append("✅ Media Library cleared (file removed/empty)")
        
        # Clean up temp files
        os.unlink(temp_vlcrc.name)
        os.unlink(temp_ml.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        # Clean up on error
        try:
            os.unlink(temp_vlcrc.name)
        except:
            pass
        try:
            os.unlink(temp_ml.name)
        except:
            pass
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: score={score}, passed={passed}, criteria_met={criteria_met}/{total_criteria}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }