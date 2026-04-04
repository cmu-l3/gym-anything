#!/usr/bin/env python3
"""
Verifier for Configure Classroom Playback task
"""

import sys
import os
import logging
import tempfile
import json
import re

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_classroom_playback(traj, env_info, task_info):
    """
    Verify configure classroom playback task completion.
    
    Checks VLC configuration for:
    1. Subtitle size increased (≥24pt or ≥150% scaling)
    2. Audio normalization/compression enabled
    3. Hardware acceleration disabled
    4. Audio gain ≥3dB
    5. Bold subtitle rendering enabled
    6. Config file accessible
    
    Pass threshold: 70% (at least 4/6 criteria, or weighted equivalent)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Copy VLC config file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        # First try to copy the config file
        try:
            copy_from_env("/tmp/vlc_classroom_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying config: {e}")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Configuration file not accessible: {str(e)}"
            }
        
        # Criterion 1: Config accessible
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Parse the config file
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            return {
                "passed": False,
                "score": 17,  # Only got config accessible
                "feedback": "Config file empty or invalid"
            }
        
        # Criterion 2: Subtitle size (font size ≥24 OR scaling ≥150%)
        subtitle_size_ok = False
        fontsize = int(config.get('freetype-fontsize', '0'))
        text_scale = int(config.get('sub-text-scale', '100'))
        
        if fontsize >= 24:
            subtitle_size_ok = True
            feedback_parts.append(f"✅ Subtitle font size: {fontsize}pt (≥24pt required)")
        elif text_scale >= 150:
            subtitle_size_ok = True
            feedback_parts.append(f"✅ Subtitle text scale: {text_scale}% (≥150% required)")
        else:
            feedback_parts.append(f"❌ Subtitle size too small (font: {fontsize}pt, scale: {text_scale}%)")
        
        if subtitle_size_ok:
            criteria_met += 1
        
        # Criterion 3: Audio normalization/compression enabled
        audio_norm_ok = False
        norm_level = float(config.get('norm-max-level', '0.0'))
        replay_gain = config.get('audio-replay-gain-mode', 'none').lower()
        
        # Check various audio normalization settings
        if norm_level > 0.0:
            audio_norm_ok = True
            feedback_parts.append(f"✅ Audio normalization level: {norm_level}")
        elif replay_gain not in ['none', 'off', '']:
            audio_norm_ok = True
            feedback_parts.append(f"✅ Audio replay gain: {replay_gain}")
        elif config.get('audio-volume-normalization', '0') == '1':
            audio_norm_ok = True
            feedback_parts.append("✅ Audio volume normalization enabled")
        elif config.get('compressor-rms-peak', '0.0') != '0.0':
            audio_norm_ok = True
            feedback_parts.append("✅ Audio compressor enabled")
        else:
            feedback_parts.append("❌ Audio normalization not enabled")
        
        if audio_norm_ok:
            criteria_met += 1
        
        # Criterion 4: Hardware acceleration disabled
        hw_accel_ok = False
        hw_accel = config.get('avcodec-hw', 'any').lower()
        
        # Check if hardware acceleration is disabled
        if hw_accel in ['none', 'disabled', 'disable', '']:
            hw_accel_ok = True
            feedback_parts.append(f"✅ Hardware acceleration: {hw_accel or 'disabled'}")
        else:
            feedback_parts.append(f"❌ Hardware acceleration still enabled: {hw_accel}")
        
        if hw_accel_ok:
            criteria_met += 1
        
        # Criterion 5: Audio gain ≥3dB
        audio_gain_ok = False
        audio_gain = float(config.get('audio-gain', '0.0'))
        
        if audio_gain >= 3.0:
            audio_gain_ok = True
            feedback_parts.append(f"✅ Audio gain: {audio_gain}dB (≥3dB required)")
        else:
            feedback_parts.append(f"❌ Audio gain too low: {audio_gain}dB (need ≥3dB)")
        
        if audio_gain_ok:
            criteria_met += 1
        
        # Criterion 6: Bold subtitle rendering enabled
        bold_subtitles_ok = False
        bold_setting = config.get('freetype-bold', '0')
        
        if bold_setting == '1' or bold_setting == 'true':
            bold_subtitles_ok = True
            feedback_parts.append("✅ Bold subtitles enabled")
        else:
            feedback_parts.append("❌ Bold subtitles not enabled")
        
        if bold_subtitles_ok:
            criteria_met += 1
        
        # Clean up temp file
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error verifying configuration: {str(e)}"
        }
    
    # Check completion marker (bonus, doesn't affect pass/fail)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_classroom_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70  # Need at least 4/6 criteria
    
    # Add summary
    feedback_summary = f"Classroom configuration: {criteria_met}/{total_criteria} criteria met"
    feedback = feedback_summary + " | " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }