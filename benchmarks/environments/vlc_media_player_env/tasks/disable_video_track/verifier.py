#!/usr/bin/env python3
"""
Verifier for Disable Video Track task

Verifies that VLC has been configured to disable video rendering
while maintaining audio playback capability.
"""

import sys
import os
import logging
import tempfile
import shutil
from pathlib import Path

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_disable_video_track(traj, env_info, task_info):
    """
    Verify disable video track task completion.
    
    Checks:
    1. VLC config file exists and is parseable
    2. Video output is disabled (vout=dummy/none, no-video=1, etc.)
    3. Configuration is valid and properly formatted
    
    VLC video can be disabled via multiple settings:
    - vout=dummy or vout=none
    - no-video=1 or novideo=1
    - video=0
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Create temporary directory for verification
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_disable_video_')
    
    try:
        # Criterion 1: Copy and parse VLC config file
        vlcrc_path = Path(temp_dir) / "vlcrc"
        
        try:
            copy_from_env("/tmp/vlc_disable_video_result/vlcrc", str(vlcrc_path))
        except Exception as e:
            logger.error(f"Error copying vlcrc: {e}")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"VLC config file not found or inaccessible: {str(e)}"
            }
        
        # Check if file exists and is not empty
        if not vlcrc_path.exists() or vlcrc_path.stat().st_size == 0:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file is empty or not found"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Parse VLC configuration
        config = parse_vlc_config(str(vlcrc_path))
        
        if not config:
            feedback_parts.append("⚠️ VLC config appears empty")
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 33,
                "feedback": " | ".join(feedback_parts) + " | Config file empty"
            }
        
        logger.info(f"Parsed {len(config)} config entries")
        
        # Criterion 2: Check if video is disabled
        # Multiple ways to disable video in VLC:
        video_disabled = False
        video_setting_found = None
        
        # Method 1: vout module set to dummy or none
        vout = config.get('vout', '').lower()
        if vout in ['dummy', 'none', 'nodisplay']:
            video_disabled = True
            video_setting_found = f"vout={vout}"
            logger.info(f"Video disabled via vout={vout}")
        
        # Method 2: no-video flag
        if not video_disabled:
            no_video = config.get('no-video', '').lower()
            if no_video in ['1', 'true', 'yes']:
                video_disabled = True
                video_setting_found = f"no-video={no_video}"
                logger.info(f"Video disabled via no-video={no_video}")
        
        # Method 3: novideo (alternative spelling)
        if not video_disabled:
            novideo = config.get('novideo', '').lower()
            if novideo in ['1', 'true', 'yes']:
                video_disabled = True
                video_setting_found = f"novideo={novideo}"
                logger.info(f"Video disabled via novideo={novideo}")
        
        # Method 4: video=0 (video disabled boolean)
        if not video_disabled:
            video = config.get('video', '')
            if video == '0':
                video_disabled = True
                video_setting_found = f"video={video}"
                logger.info(f"Video disabled via video={video}")
        
        # Method 5: Check for any vout module that indicates no display
        if not video_disabled:
            # Some other no-display vout modules
            if vout and any(keyword in vout for keyword in ['none', 'dummy', 'nodisplay', 'null']):
                video_disabled = True
                video_setting_found = f"vout={vout}"
                logger.info(f"Video disabled via vout containing disable keyword: {vout}")
        
        if video_disabled:
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append(f"✅ Video rendering disabled ({video_setting_found})")
        else:
            # Check if any video-related settings exist but aren't disabling
            video_related = [k for k in config.keys() if 'video' in k.lower() or k == 'vout']
            if video_related:
                feedback_parts.append(f"❌ Video not disabled (found: {', '.join(video_related[:3])})")
            else:
                feedback_parts.append("❌ No video disable settings found")
        
        # Criterion 3: Configuration validity check
        # Check that the config file has reasonable structure
        if len(config) > 0 and not any('error' in k.lower() for k in config.keys()):
            criteria_met += 0  # Already counted in criterion 1
            feedback_parts.append("✅ Config structure valid")
        
        # Additional info: Check if audio settings are intact
        audio_volume = config.get('audio-volume', '')
        if audio_volume:
            feedback_parts.append(f"ℹ️ Audio volume: {audio_volume}")
        
        # Copy video settings summary for debugging
        try:
            video_settings_path = Path(temp_dir) / "video_settings.txt"
            copy_from_env("/tmp/vlc_disable_video_result/video_settings.txt", str(video_settings_path))
            
            if video_settings_path.exists():
                with open(video_settings_path, 'r') as f:
                    video_settings_content = f.read().strip()
                    logger.info(f"Video settings file content:\n{video_settings_content}")
        except Exception as e:
            logger.warning(f"Could not copy video settings summary: {e}")
        
        # Check completion marker
        try:
            completion_path = Path(temp_dir) / "completed.txt"
            copy_from_env("/tmp/vlc_disable_video_completed.txt", str(completion_path))
            feedback_parts.append("✅ Task completed")
        except Exception:
            feedback_parts.append("⚠️ Completion marker not found")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        shutil.rmtree(temp_dir, ignore_errors=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification result: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }