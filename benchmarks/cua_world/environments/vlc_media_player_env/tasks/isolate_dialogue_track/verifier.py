#!/usr/bin/env python3
"""
Verifier for Isolate Dialogue Track task
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


def verify_isolate_dialogue(traj, env_info, task_info):
    """
    Verify isolate dialogue track task completion.

    Checks:
    1. VLC config file accessible and parseable
    2. Audio filter is enabled
    3. Center extraction or related settings are configured

    Audio filters that indicate center channel extraction:
    - audio-filter=headphone (with Dolby Surround mode)
    - audio-filter=spatializer
    - Stereo mode modifications
    - Channel mixer settings
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/vlc_dialogue_result.json", temp_result.name)

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        config_found = result.get('config_found', False)
        
        if not config_found:
            os.unlink(temp_result.name)
            return {"passed": False, "score": 0, "feedback": "VLC config file not found"}

        criteria_met += 1
        feedback_parts.append("✅ Config file accessible")

        # Get filter settings
        filter_settings = result.get('filter_settings', {})
        settings_count = result.get('settings_count', 0)

        if not isinstance(filter_settings, dict) or settings_count == 0:
            feedback_parts.append("❌ No audio filter settings found")
        else:
            feedback_parts.append(f"Found {settings_count} audio settings")

            # Check for audio filter enabled
            audio_filter = filter_settings.get('audio-filter', '')
            
            # Keywords indicating center extraction or spatial audio manipulation
            center_extraction_keywords = [
                'headphone', 'spatializer', 'channel', 'center', 
                'stereo', 'surround', 'mix'
            ]
            
            filter_enabled = False
            center_extraction_configured = False
            
            # Check audio-filter setting
            if audio_filter:
                criteria_met += 1
                filter_enabled = True
                feedback_parts.append(f"✅ Audio filter enabled: {audio_filter}")
                
                # Check if it's a relevant filter
                if any(keyword in audio_filter.lower() for keyword in center_extraction_keywords):
                    center_extraction_configured = True
            
            # Check for specific filter configurations
            headphone_settings = {k: v for k, v in filter_settings.items() if k.startswith('headphone')}
            spatializer_settings = {k: v for k, v in filter_settings.items() if k.startswith('spatializer')}
            stereo_mode = filter_settings.get('stereo-mode', '')
            channel_mixer = filter_settings.get('audio-channel-mixer', '')
            
            if headphone_settings:
                criteria_met += 0.5
                filter_enabled = True
                center_extraction_configured = True
                feedback_parts.append(f"✅ Headphone effect configured ({len(headphone_settings)} settings)")
            
            if spatializer_settings:
                criteria_met += 0.5
                filter_enabled = True
                center_extraction_configured = True
                feedback_parts.append(f"✅ Spatializer configured ({len(spatializer_settings)} settings)")
            
            if stereo_mode:
                criteria_met += 0.5
                filter_enabled = True
                feedback_parts.append(f"✅ Stereo mode set: {stereo_mode}")
                
                # Check if stereo mode indicates center extraction
                if any(keyword in stereo_mode.lower() for keyword in ['mono', 'center', 'left', 'right']):
                    center_extraction_configured = True
            
            if channel_mixer:
                criteria_met += 0.5
                filter_enabled = True
                center_extraction_configured = True
                feedback_parts.append(f"✅ Channel mixer configured: {channel_mixer}")
            
            # Final criterion: center extraction specifically configured
            if center_extraction_configured:
                criteria_met += 1
                feedback_parts.append("✅ Center extraction/spatial filter configured")
            else:
                if filter_enabled:
                    feedback_parts.append("⚠️ Audio filter enabled but may not extract center channel")
                else:
                    feedback_parts.append("❌ No center extraction filter configured")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading dialogue result: {str(e)}"}

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_dialogue_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Also check the raw vlcrc file for additional validation
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_dialogue_vlcrc.txt", temp_vlcrc.name)
        
        with open(temp_vlcrc.name, 'r') as f:
            vlcrc_content = f.read()
        
        # Search for any audio filter mentions in raw config
        audio_filter_lines = [line for line in vlcrc_content.split('\n') 
                             if 'audio-filter' in line.lower() or 'headphone' in line.lower() 
                             or 'spatializer' in line.lower()]
        
        if audio_filter_lines and criteria_met < total_criteria:
            # Give partial credit if we found filters in raw config
            logger.info(f"Found audio filters in raw config: {audio_filter_lines[:3]}")
        
        os.unlink(temp_vlcrc.name)
    except Exception as e:
        logger.warning(f"Could not read raw vlcrc: {e}")

    # Cap criteria at total
    criteria_met = min(criteria_met, total_criteria)

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }