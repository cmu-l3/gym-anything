#!/usr/bin/env python3
"""
Verifier for Configure Audio Output Device task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_audio_device_configuration(traj, env_info, task_info):
    """
    Verify configure audio output device task completion.
    
    Checks:
    1. VLC config file exists and is accessible
    2. Audio output module is explicitly set (not "auto")
    3. Device-specific settings indicate non-default/HDMI configuration
    
    VLC audio configuration:
    - aout=auto (default, not configured)
    - aout=alsa, aout=pulse, etc. (explicitly configured)
    - alsa-audio-device=<device> (ALSA device selection)
    - pulse-sink=<sink> (PulseAudio sink selection)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy VLC config file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_audio_config.txt", temp_config.name)
        
        # Parse VLC config using utility function
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            return {"passed": False, "score": 0, "feedback": "VLC config file empty or invalid"}
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Criterion 2: Check audio output module
        aout = config.get('aout', '')
        
        if aout and aout != 'auto' and aout != '':
            criteria_met += 1
            feedback_parts.append(f"✅ Audio module configured: {aout}")
            
            # Criterion 3: Check device-specific settings
            alsa_device = config.get('alsa-audio-device', '')
            pulse_sink = config.get('pulse-sink', '')
            
            device_configured = False
            device_is_hdmi = False
            
            if alsa_device:
                device_configured = True
                # Check if device suggests HDMI or non-default
                if 'hdmi' in alsa_device.lower():
                    device_is_hdmi = True
                    criteria_met += 1
                    feedback_parts.append(f"✅ ALSA HDMI device configured: {alsa_device}")
                elif alsa_device != 'default' and alsa_device != 'hw:0,0':
                    criteria_met += 0.7  # Partial credit for non-default
                    feedback_parts.append(f"⚠️ ALSA non-default device configured: {alsa_device}")
                else:
                    feedback_parts.append(f"⚠️ ALSA device set but seems like default: {alsa_device}")
            
            elif pulse_sink:
                device_configured = True
                # Check if sink suggests HDMI or non-default
                if 'hdmi' in pulse_sink.lower():
                    device_is_hdmi = True
                    criteria_met += 1
                    feedback_parts.append(f"✅ PulseAudio HDMI sink configured: {pulse_sink}")
                elif pulse_sink != 'auto' and pulse_sink != 'default':
                    criteria_met += 0.7  # Partial credit for non-default
                    feedback_parts.append(f"⚠️ PulseAudio non-default sink configured: {pulse_sink}")
                else:
                    feedback_parts.append(f"⚠️ PulseAudio sink set but seems like default: {pulse_sink}")
            
            else:
                # Module is set but no specific device
                criteria_met += 0.3  # Small partial credit
                feedback_parts.append(f"⚠️ Audio module set but no specific device configured")
        
        elif aout == 'auto' or not aout:
            feedback_parts.append("❌ Audio output still set to automatic (default)")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading VLC config: {str(e)}"}
    
    # Also try to load the JSON result for additional context
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_audio_device_result.json", temp_json.name)
        
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        
        # Add context from JSON if available
        if result.get('runtime_captured'):
            feedback_parts.append("ℹ️ Runtime settings captured")
        
        os.unlink(temp_json.name)
    except Exception as e:
        # JSON file is optional
        logger.debug(f"Could not load JSON result: {e}")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_device_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }