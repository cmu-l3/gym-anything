#!/usr/bin/env python3
"""
Verifier for Verify Surround Channels task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_surround_channels(traj, env_info, task_info):
    """
    Verify surround channels configuration task completion.
    
    Checks:
    1. VLC config file exists and is parseable
    2. Audio device changed to multi-channel capable device
    3. Stereo downmixing is disabled
    
    This task tests the agent's ability to navigate VLC preferences
    and configure audio output settings for surround sound.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy audio settings JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/vlc_audio_settings.json", temp_json.name)
        
        # Parse JSON result
        with open(temp_json.name, 'r') as f:
            settings = json.load(f)
        
        config_found = settings.get('config_found', False)
        
        if not config_found:
            os.unlink(temp_json.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file not found - preferences may not have been saved"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        
        # Get settings
        audio_device = settings.get('audio_device', '').lower()
        downmix = settings.get('downmix_to_stereo', '')
        aout_module = settings.get('aout_module', '')
        
        # Criterion 2: Check if audio device was changed to multi-channel
        # Initial device: "alsa_output.pci-0000_00_1b.0.analog-stereo"
        # Look for indicators of multi-channel devices
        multichannel_indicators = [
            'hdmi', 'usb', 'displayport', 'surround', '5.1', '7.1',
            'digital', 'spdif', 'multichannel', 'iec958'
        ]
        
        # Check if device changed from the initial stereo device
        initial_stereo_device = 'alsa_output.pci-0000_00_1b.0.analog-stereo'
        device_changed = audio_device != initial_stereo_device.lower()
        
        # Check if new device suggests multi-channel capability
        is_multichannel = any(indicator in audio_device for indicator in multichannel_indicators)
        
        # Check if still using clearly stereo device
        stereo_indicators = ['stereo', 'analog-stereo', 'built-in']
        is_stereo = any(indicator in audio_device for indicator in stereo_indicators)
        
        if is_multichannel:
            criteria_met += 1.2
            feedback_parts.append(f"✅ Multi-channel device configured: {audio_device[:50]}")
        elif device_changed and not is_stereo:
            criteria_met += 0.8
            feedback_parts.append(f"⚠️ Device changed but unclear if multi-channel: {audio_device[:50]}")
        elif device_changed:
            criteria_met += 0.4
            feedback_parts.append(f"⚠️ Device changed but still appears to be stereo: {audio_device[:50]}")
        else:
            feedback_parts.append("❌ Audio device unchanged (still using built-in stereo)")
        
        # Criterion 3: Check if downmixing was disabled
        # Initial: downmix_to_stereo=1 (enabled)
        # Target: downmix_to_stereo=0 or removed
        
        if downmix == '0' or downmix == '':
            criteria_met += 1
            if downmix == '0':
                feedback_parts.append("✅ Stereo downmixing explicitly disabled")
            else:
                feedback_parts.append("✅ Stereo downmixing setting removed (disabled)")
        elif downmix == '1':
            feedback_parts.append("❌ Stereo downmixing still enabled (will convert 5.1 → stereo)")
        else:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Downmix setting unclear: {downmix}")
        
        os.unlink(temp_json.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading audio settings: {str(e)}"
        }
    
    # Also copy full config for debugging
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_config.txt", temp_config.name)
        
        with open(temp_config.name, 'r') as f:
            config_content = f.read()
        
        # Additional checks from raw config
        if 'spdif' in config_content.lower() and 'spdif=1' in config_content.lower():
            feedback_parts.append("✓ S/PDIF enabled (good for multi-channel)")
        
        if 'channels' in config_content.lower():
            channels_line = [line for line in config_content.split('\n') if 'channels=' in line.lower()]
            if channels_line:
                feedback_parts.append(f"✓ Channel config found: {channels_line[0].strip()}")
        
        os.unlink(temp_config.name)
        
    except Exception:
        # Config file copy is optional, don't fail if not available
        pass
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_surround_completed.txt", temp_marker.name)
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Normalize score to 0-100 range
    # Max criteria_met is 3.2, normalize to 3 for percentage
    normalized_score = min(criteria_met / 3.0, 1.0)
    score = int(normalized_score * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    
    # Add hints if failed
    if not passed:
        hints = []
        if not device_changed:
            hints.append("Hint: Open Tools → Preferences → Audio and change the output device")
        if downmix == '1':
            hints.append("Hint: Disable 'Downmix to stereo' checkbox in audio preferences")
        if not is_multichannel and device_changed:
            hints.append("Hint: Look for devices with 'HDMI', 'USB', or 'Surround' in the name")
        
        if hints:
            feedback += " | " + " | ".join(hints)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }