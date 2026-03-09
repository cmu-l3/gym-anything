#!/usr/bin/env python3
"""
Verifier for Correct Aspect Ratio task

Checks that:
1. VLC configuration contains aspect ratio override set to 4:3
2. The override is properly formatted
3. The original video still exists and has incorrect metadata (unchanged)
"""

import json
import logging
import os
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple

import sys

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_config(filepath: str) -> Dict[str, str]:
    """Parse VLC configuration file."""
    config = {}
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
        logger.info(f"Parsed {len(config)} config entries from {filepath}")
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
    return config


def check_aspect_ratio_setting(config: Dict[str, str]) -> Tuple[bool, str, str]:
    """
    Check if aspect ratio is correctly set to 4:3.
    
    Valid formats:
    - aspect-ratio=4:3
    - aspect-ratio="4:3"
    - vout-aspect-ratio=4:3
    - custom-aspect-ratios=4:3
    - qt-aspect-ratio=4:3
    
    Returns:
        Tuple of (is_correct, setting_found, feedback_message)
    """
    # Check various possible configuration keys
    aspect_keys = [
        'aspect-ratio',
        'vout-aspect-ratio',
        'custom-aspect-ratios',
        'qt-aspect-ratio',
        'monitor-par',
        'force-aspect-ratio'
    ]
    
    for key in aspect_keys:
        if key in config:
            value = config[key].strip('"').strip("'").strip()
            logger.info(f"Found {key}={value}")
            
            # Check if it's set to 4:3
            if value == '4:3':
                return True, f"{key}=4:3", f"Aspect ratio correctly set to 4:3 (via {key})"
            
            # Also accept decimal equivalent (1.333...)
            try:
                # Handle ratio format like "4:3"
                if ':' in value:
                    ratio_float = eval(value.replace(':', '/'))
                else:
                    ratio_float = float(value)
                
                expected_ratio = 4.0 / 3.0
                if abs(ratio_float - expected_ratio) < 0.01:
                    return True, f"{key}={value}", f"Aspect ratio correctly set (via {key}={value} ≈ 4:3)"
            except:
                pass
            
            # If we found an aspect ratio setting but it's wrong
            return False, f"{key}={value}", f"Aspect ratio found but set to {value}, not 4:3"
    
    return False, "", "No aspect ratio override found in VLC configuration"


def verify_correct_aspect_ratio(traj, env_info, task_info):
    """
    Main verification function.
    
    Returns dict with:
    - passed: bool
    - score: float (0 to 100)
    - feedback: str
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
    
    # Create temp directory for copying files
    temp_dir = tempfile.mkdtemp(prefix='aspect_verify_')
    
    try:
        # Criterion 1: Check if VLC config file exists and is accessible
        vlcrc_path = os.path.join(temp_dir, "vlcrc")
        
        try:
            copy_from_env("/tmp/task_export/vlcrc", vlcrc_path)
        except Exception as e:
            logger.error(f"Failed to copy vlcrc: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"VLC configuration file not found or inaccessible: {str(e)}"
            }
        
        if not os.path.exists(vlcrc_path) or os.path.getsize(vlcrc_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC configuration file is empty or not found"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Parse VLC configuration
        config = parse_vlc_config(vlcrc_path)
        
        if not config:
            logger.warning("VLC config is empty or unreadable")
            # Still give partial credit for having the file
            feedback_parts.append("⚠️ Config file exists but appears empty")
        
        # Criterion 2 & 3: Check aspect ratio setting
        aspect_correct, setting_found, aspect_msg = check_aspect_ratio_setting(config)
        
        if aspect_correct:
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append(f"✅ {aspect_msg}")
            logger.info(f"Aspect ratio correctly configured: {setting_found}")
        elif setting_found:
            # Found an aspect ratio setting but it's wrong
            criteria_met += 1  # Partial credit
            feedback_parts.append(f"⚠️ {aspect_msg}")
            logger.warning(f"Incorrect aspect ratio: {setting_found}")
        else:
            feedback_parts.append(f"❌ {aspect_msg}")
            logger.error("No aspect ratio override found in config")
        
        # Additional check: Verify the original video still exists and is unchanged
        # (We want to make sure agent didn't re-encode the video)
        try:
            video_info_path = os.path.join(temp_dir, "video_info.json")
            copy_from_env("/tmp/task_export/video_info.json", video_info_path)
            
            with open(video_info_path, 'r') as f:
                video_info = json.load(f)
            
            # Check that video still has wrong metadata (we didn't re-encode it)
            streams = video_info.get('streams', [])
            if streams:
                stream = streams[0]
                dar = stream.get('display_aspect_ratio', '')
                width = stream.get('width', 0)
                height = stream.get('height', 0)
                
                logger.info(f"Video properties: {width}x{height}, DAR: {dar}")
                
                # Good: video metadata unchanged (still has wrong 16:9)
                if '16:9' in dar and width == 640 and height == 480:
                    feedback_parts.append("✅ Original video unchanged (correct approach)")
                    logger.info("Video metadata correctly unchanged - agent used display override, not re-encoding")
                elif width == 640 and height == 480:
                    # Video dimensions correct, aspect ratio might have been fixed
                    feedback_parts.append("⚠️ Video dimensions correct")
        except Exception as e:
            logger.warning(f"Could not verify video info: {e}")
            # Don't penalize if we can't check this
        
        # Check completion marker
        try:
            completion_path = os.path.join(temp_dir, "completion.txt")
            copy_from_env("/tmp/vlc_aspect_completed.txt", completion_path)
            feedback_parts.append("✅ Task completed")
        except:
            feedback_parts.append("⚠️ Completion marker not found")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        try:
            import shutil
            shutil.rmtree(temp_dir)
        except:
            pass
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    result = {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
    
    logger.info(f"Verification result: {result}")
    
    return result
