#!/usr/bin/env python3
"""
Verifier for Switch Video Angle task
"""

import sys
import os
import logging
import tempfile
import re
import subprocess
import json
from pathlib import Path
from typing import Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_switch_video_angle(traj, env_info, task_info):
    """
    Verify switch video angle task completion.
    
    Checks:
    1. Multi-track video file exists and is valid
    2. VLC was running with the concert video
    3. Evidence of track switching (CLI args, logs, DBus)
    4. Visual confirmation via screenshot (bonus)
    
    Scoring:
    - Video valid: 2 points
    - VLC running: 2 points
    - Track switch evidence: 4 points
    - Visual confirmation: 2 points (bonus)
    Total: 10 points, passing: 6 points (60%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    max_score = 10
    feedback_parts = []
    
    # Check 1: Verify multi-track video exists and is valid
    video_check = check_video_file(copy_from_env)
    if video_check[0]:
        score += 2
        feedback_parts.append(video_check[1])
    else:
        feedback_parts.append(f"❌ Video check failed: {video_check[1]}")
        # If video doesn't exist, task setup failed
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
    
    # Check 2: VLC was running with the concert video
    vlc_check = check_vlc_running(copy_from_env)
    if vlc_check[0]:
        score += 2
        feedback_parts.append(vlc_check[1])
    else:
        feedback_parts.append(vlc_check[1])
    
    # Check 3: Evidence of video track switching (most important)
    track_check = check_track_switch_evidence(copy_from_env)
    if track_check[0]:
        score += 4
        feedback_parts.append(track_check[1])
    else:
        feedback_parts.append(track_check[1])
    
    # Check 4: Visual confirmation (bonus)
    visual_check = check_visual_evidence(copy_from_env)
    if visual_check[0]:
        score += 2
        feedback_parts.append(visual_check[1])
    elif visual_check[1]:  # If there's feedback but not successful
        feedback_parts.append(visual_check[1])
    
    # Determine success
    passed = score >= 6
    
    feedback = " | ".join(feedback_parts)
    feedback += f"\n{'='*50}\nScore: {score}/{max_score} - {'PASS ✓' if passed else 'FAIL ✗'}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }


def check_video_file(copy_fn) -> Tuple[bool, str]:
    """Verify the multi-track video file exists and has multiple tracks."""
    temp_dir = tempfile.mkdtemp(prefix='vlc_verify_video_')
    
    try:
        video_path = '/home/ga/Videos/concert_multiangle.mkv'
        local_path = Path(temp_dir) / 'concert.mkv'
        
        try:
            copy_fn(video_path, str(local_path))
        except Exception as e:
            return False, f"Video file not found: {e}"
        
        if not local_path.exists() or local_path.stat().st_size < 1000:
            return False, "Video file not found or empty"
        
        # Check for multiple video streams using ffprobe
        try:
            cmd = [
                'ffprobe', '-v', 'error',
                '-select_streams', 'v',
                '-show_entries', 'stream=index,codec_name',
                '-of', 'csv=p=0',
                str(local_path)
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                return False, f"ffprobe failed: {result.stderr}"
            
            track_lines = [line for line in result.stdout.strip().split('\n') if line]
            track_count = len(track_lines)
            
            if track_count < 2:
                return False, f"Video has only {track_count} track(s), expected multiple"
            
            return True, f"✅ Video has {track_count} video tracks"
            
        except Exception as e:
            return False, f"Error checking video tracks: {e}"
        
    finally:
        # Cleanup
        import shutil
        shutil.rmtree(temp_dir, ignore_errors=True)


def check_vlc_running(copy_fn) -> Tuple[bool, str]:
    """Check if VLC was running with the concert video."""
    temp_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
    
    try:
        try:
            copy_fn('/tmp/task_export/vlc_processes.txt', temp_file.name)
        except Exception as e:
            return False, f"⚠️ Could not verify VLC status: {e}"
        
        with open(temp_file.name, 'r') as f:
            content = f.read()
        
        os.unlink(temp_file.name)
        
        if 'concert_multiangle' in content or ('vlc' in content.lower() and len(content) > 10):
            return True, "✅ VLC was running with concert video"
        
        return False, "❌ VLC not running with target video"
        
    except Exception as e:
        return False, f"⚠️ Could not verify VLC status: {e}"


def check_track_switch_evidence(copy_fn) -> Tuple[bool, str]:
    """Look for evidence of video track switching."""
    
    # Strategy 1: Check if VLC was launched with explicit track selection
    try:
        temp_proc = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
        copy_fn('/tmp/task_export/vlc_processes.txt', temp_proc.name)
        
        with open(temp_proc.name, 'r') as f:
            proc_content = f.read()
        
        os.unlink(temp_proc.name)
        
        # Look for video-track-id flag in command line
        if '--video-track-id=1' in proc_content or '--video-track=1' in proc_content:
            return True, "✅ Track 1 explicitly selected via command line (--video-track-id=1)"
        
        # Also check for vtrack (short form)
        if '--vtrack=1' in proc_content or '--vtrack-id=1' in proc_content:
            return True, "✅ Track 1 explicitly selected via command line (--vtrack=1)"
        
    except Exception as e:
        logger.warning(f"Could not check process args: {e}")
    
    # Strategy 2: Check VLC logs for track switching messages
    log_files = [
        ('vlc-log.txt', 'VLC log'),
        ('vlc_messages.log', 'VLC messages'),
        ('track_analysis.txt', 'track analysis')
    ]
    
    for log_file, log_name in log_files:
        try:
            temp_log = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
            copy_fn(f'/tmp/task_export/{log_file}', temp_log.name)
            
            with open(temp_log.name, 'r') as f:
                log_content = f.read().lower()
            
            os.unlink(temp_log.name)
            
            # Look for track selection patterns
            patterns = [
                (r'video.{0,30}track.{0,10}1\b', 'video track 1'),
                (r'select.{0,20}track.{0,10}1\b', 'select track 1'),
                (r'switch.{0,20}track', 'track switch'),
                (r'track.{0,10}1.{0,20}select', 'track 1 selected'),
                (r'using.{0,20}video.{0,20}track.{0,10}1', 'using video track 1'),
                (r'es out.{0,30}video.{0,20}1', 'ES video track 1'),
            ]
            
            for pattern, description in patterns:
                if re.search(pattern, log_content, re.IGNORECASE):
                    return True, f"✅ Track switch detected in {log_name} ({description})"
            
        except Exception as e:
            logger.debug(f"Could not check {log_name}: {e}")
            continue
    
    # Strategy 3: Check DBus state
    try:
        temp_dbus = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
        copy_fn('/tmp/task_export/vlc_dbus_state.txt', temp_dbus.name)
        
        with open(temp_dbus.name, 'r') as f:
            dbus_content = f.read().lower()
        
        os.unlink(temp_dbus.name)
        
        # Look for track information in DBus output
        if 'track' in dbus_content and any(x in dbus_content for x in ['video', 'stream']):
            # This is a weak signal, only use as supporting evidence
            logger.info("Found track-related info in DBus output")
        
    except Exception as e:
        logger.debug(f"Could not check DBus state: {e}")
    
    # Strategy 4: Check VLC config for saved track preference
    try:
        temp_config = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
        copy_fn('/tmp/task_export/vlc_config_tracks.txt', temp_config.name)
        
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
        
        os.unlink(temp_config.name)
        
        # Look for video-track settings
        if 'video-track' in config_content and '1' in config_content:
            return True, "✅ Video track 1 found in VLC configuration"
        
    except Exception as e:
        logger.debug(f"Could not check VLC config: {e}")
    
    return False, "❌ No evidence of track switching found"


def check_visual_evidence(copy_fn) -> Tuple[bool, str]:
    """Check screenshot for visual confirmation of Track 1 (red background)."""
    
    # Try both screenshot files
    screenshot_files = ['final_screenshot.png', 'vlc_window.png']
    
    for screenshot_file in screenshot_files:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_fn(f'/tmp/task_export/{screenshot_file}', temp_img.name)
            
            # Try to analyze screenshot for red color (Track 1 indicator)
            try:
                from PIL import Image
                import numpy as np
                
                img = Image.open(temp_img.name)
                
                # Convert to RGB if needed
                if img.mode != 'RGB':
                    img = img.convert('RGB')
                
                img_array = np.array(img)
                
                # Calculate average color channels
                mean_red = np.mean(img_array[:, :, 0])
                mean_green = np.mean(img_array[:, :, 1])
                mean_blue = np.mean(img_array[:, :, 2])
                
                logger.info(f"Screenshot color analysis: R={mean_red:.1f}, G={mean_green:.1f}, B={mean_blue:.1f}")
                
                # Track 1 should have predominantly red (red > 120 and red > green and red > blue)
                if mean_red > 120 and mean_red > mean_green + 30 and mean_red > mean_blue + 30:
                    os.unlink(temp_img.name)
                    return True, f"✅ Screenshot shows Track 1 (red background detected: R={mean_red:.0f})"
                
                # Track 0 is blue
                elif mean_blue > 120 and mean_blue > mean_red + 30 and mean_blue > mean_green + 30:
                    os.unlink(temp_img.name)
                    return False, f"⚠️ Screenshot shows Track 0 (blue background: B={mean_blue:.0f})"
                
                # Track 2 is green
                elif mean_green > 120 and mean_green > mean_red + 30 and mean_green > mean_blue + 30:
                    os.unlink(temp_img.name)
                    return False, f"⚠️ Screenshot shows Track 2 (green background: G={mean_green:.0f})"
                
                else:
                    logger.info("Screenshot color analysis inconclusive")
                
            except ImportError:
                logger.warning("PIL/numpy not available for image analysis")
            except Exception as e:
                logger.warning(f"Image analysis failed: {e}")
            
            os.unlink(temp_img.name)
            
        except Exception as e:
            logger.debug(f"Could not analyze {screenshot_file}: {e}")
            continue
    
    return False, "⚠️ Visual confirmation inconclusive"
