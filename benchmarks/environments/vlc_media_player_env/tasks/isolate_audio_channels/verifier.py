#!/usr/bin/env python3
"""
Verifier for Isolate Audio Channels task
"""

import sys
import os
import logging
import tempfile
import json

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_isolate_audio_channels(traj, env_info, task_info):
    """
    Verify isolate audio channels task completion.

    Checks:
    1. VLC config file exists and is parseable
    2. Audio channel isolation configured (filters, stereo-mode, etc.)
    3. Test results log created by agent
    4. Evidence of systematic approach
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 5
    feedback_parts = []

    # Criterion 1: Copy and parse result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/vlc_channel_result.json", temp_result.name)

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Channel isolation result accessible")

        # Get settings from result
        audio_settings = result.get('audio_settings', {})
        settings_count = result.get('settings_count', 0)
        config_found = result.get('config_found', False)
        test_log_found = result.get('test_log_found', False)

        logger.info(f"Audio settings: {audio_settings}")
        logger.info(f"Settings count: {settings_count}")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading channel result: {str(e)}"}

    # Criterion 2: Check VLC config exists
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    config_parsed = False
    vlc_config = {}
    
    try:
        copy_from_env("/tmp/vlc_channel_config.txt", temp_config.name)
        
        if config_found:
            criteria_met += 1
            feedback_parts.append("✅ VLC config file found")
            
            # Parse the config
            try:
                vlc_config = parse_vlc_config(temp_config.name)
                config_parsed = True
                logger.info(f"Parsed {len(vlc_config)} config settings")
            except Exception as e:
                logger.warning(f"Could not parse VLC config: {e}")
        else:
            feedback_parts.append("❌ VLC config file not found")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.warning(f"Could not copy VLC config: {e}")
        feedback_parts.append("⚠️ VLC config not accessible")

    # Criterion 3: Check for audio channel isolation configuration
    # Valid indicators: audio-filter, stereo-mode, or other audio manipulation settings
    channel_config_found = False
    config_type = ""
    
    # Check audio settings from JSON
    if isinstance(audio_settings, dict) and audio_settings:
        # Check for relevant audio settings
        relevant_keys = ['audio-filter', 'stereo-mode', 'audio_mode', 'stereo_mode', 
                        'headphone-dim', 'remap', 'channelmixer', 'extrastereo']
        
        found_settings = []
        for key in relevant_keys:
            if key in audio_settings:
                value = audio_settings[key]
                if value and str(value).strip() and str(value) not in ['', 'none', 'None']:
                    found_settings.append(f"{key}={value}")
                    channel_config_found = True
        
        if found_settings:
            config_type = ", ".join(found_settings)
            logger.info(f"Found audio config: {config_type}")
    
    # Also check parsed VLC config directly
    if config_parsed and vlc_config:
        for key in ['audio-filter', 'stereo-mode', 'headphone-dim', 'remap', 'channelmixer']:
            if key in vlc_config:
                value = vlc_config[key]
                if value and str(value).strip() and str(value) not in ['', 'none', 'None']:
                    if not channel_config_found:
                        config_type = f"{key}={value}"
                    channel_config_found = True
                    logger.info(f"Found {key} in vlcrc: {value}")
    
    if channel_config_found:
        criteria_met += 2  # Double weight for main criterion
        feedback_parts.append(f"✅ Audio channel configuration detected: {config_type}")
    else:
        feedback_parts.append("❌ No audio channel isolation configuration found")
        feedback_parts.append("   Expected: audio-filter, stereo-mode, or related settings")

    # Criterion 4: Check for test results log
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        copy_from_env("/tmp/vlc_channel_test_log.txt", temp_log.name)
        
        if test_log_found:
            with open(temp_log.name, 'r') as f:
                log_content = f.read()
            
            if log_content.strip():
                criteria_met += 1
                log_lines = len(log_content.strip().split('\n'))
                feedback_parts.append(f"✅ Test results log created ({log_lines} lines)")
                
                # Check if log mentions relevant terms
                log_lower = log_content.lower()
                relevant_terms = ['channel', 'front', 'right', 'speaker', 'test', 'audio', 'isolate']
                found_terms = [term for term in relevant_terms if term in log_lower]
                
                if len(found_terms) >= 2:
                    logger.info(f"Log contains relevant terms: {found_terms}")
            else:
                feedback_parts.append("⚠️ Test results log is empty")
        else:
            feedback_parts.append("⚠️ Test results log not found (optional but recommended)")
        
        os.unlink(temp_log.name)
        
    except Exception as e:
        logger.warning(f"Could not read test log: {e}")
        feedback_parts.append("⚠️ Test results log not accessible")

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_channel_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 60  # 60% threshold as specified

    # Final feedback
    if passed:
        feedback_parts.insert(0, f"✅ PASS - Audio channel isolation configured ({score}%)")
    else:
        feedback_parts.insert(0, f"❌ FAIL - Insufficient configuration ({score}%)")

    feedback_parts.append(f"\nScore: {criteria_met}/{total_criteria} criteria met")

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }