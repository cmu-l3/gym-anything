#!/usr/bin/env python3
"""
Verifier for Verify Mono Compatibility task

This verifier checks if VLC has been configured to downmix stereo audio to mono,
which is essential for podcast producers testing mobile compatibility.
"""

import sys
import os
import logging
import tempfile
import json
import shutil

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mono_compatibility(traj, env_info, task_info):
    """
    Verify that VLC is configured for mono audio output.
    
    Checks multiple possible mono configuration methods:
    1. audio-filter contains 'mono'
    2. mono=1 setting
    3. stereo-to-mono=1 setting
    4. channels=1 setting
    5. channel-mixer set to mono
    
    Args:
        traj: Trajectory information
        env_info: Environment info with copy_from_env function
        task_info: Task information
        
    Returns:
        Dict with passed (bool), score (int), feedback (str), and metadata
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available",
            "metadata": {}
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    metadata = {}
    
    temp_dir = tempfile.mkdtemp(prefix='vlc_mono_verify_')
    
    try:
        # Copy VLC configuration file
        host_config = os.path.join(temp_dir, 'vlcrc')
        
        try:
            copy_from_env('/tmp/vlc_mono_vlcrc', host_config)
        except Exception as e:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to copy VLC config: {e}",
                "metadata": {}
            }
        
        if not os.path.exists(host_config):
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file not found after copy",
                "metadata": {}
            }
        
        # Criterion 1: Config file accessible and parseable
        config = parse_vlc_config(host_config)
        
        if not config:
            shutil.rmtree(temp_dir, ignore_errors=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse VLC config",
                "metadata": {}
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Config accessible")
        
        # Criterion 2 & 3: Check for mono configuration
        # Multiple methods can enable mono output in VLC
        mono_enabled = False
        methods_found = []
        
        # Method 1: audio-filter with 'mono' module
        audio_filter = config.get('audio-filter', '')
        if 'mono' in audio_filter.lower():
            mono_enabled = True
            methods_found.append("audio-filter=mono")
            logger.info(f"Found mono in audio-filter: {audio_filter}")
        
        # Method 2: Explicit mono setting
        if config.get('mono', '0') == '1':
            mono_enabled = True
            methods_found.append("mono=1")
            logger.info("Found mono=1 setting")
        
        # Method 3: stereo-to-mono conversion
        stereo_to_mono = config.get('stereo-to-mono', '0')
        if stereo_to_mono == '1':
            mono_enabled = True
            methods_found.append("stereo-to-mono=1")
            logger.info("Found stereo-to-mono=1 setting")
        
        # Method 4: channel count set to 1
        channels = config.get('channels', '')
        if channels == '1':
            mono_enabled = True
            methods_found.append("channels=1")
            logger.info("Found channels=1 setting")
        
        # Method 5: channel mixer set to mono
        channel_mixer = config.get('audio-channel-mixer', '')
        aout_channel_mixer = config.get('aout-channel-mixer', '')
        if 'mono' in channel_mixer.lower() or 'mono' in aout_channel_mixer.lower():
            mono_enabled = True
            methods_found.append("channel-mixer=mono")
            logger.info(f"Found mono in channel mixer: {channel_mixer or aout_channel_mixer}")
        
        # Store metadata about what was found
        metadata = {
            'mono_enabled': mono_enabled,
            'methods_found': methods_found,
            'audio_filter': audio_filter,
            'config_keys_checked': ['audio-filter', 'mono', 'stereo-to-mono', 'channels', 
                                   'audio-channel-mixer', 'aout-channel-mixer'],
            'total_config_keys': len(config)
        }
        
        if not mono_enabled:
            feedback_parts.append(
                "❌ Mono output not enabled. "
                "Try: Tools → Preferences → Show All → Audio → Filters → Enable 'Mono'"
            )
            
            # Provide helpful debugging info
            logger.warning("Mono not detected. Config keys present:")
            logger.warning(f"audio-filter: {audio_filter}")
            logger.warning(f"All audio-related keys: {[k for k in config.keys() if 'audio' in k.lower()]}")
        else:
            criteria_met += 2  # Award full points for mono enabled
            method_str = ", ".join(methods_found)
            feedback_parts.append(f"✅ Mono enabled: {method_str}")
            feedback_parts.append(
                "✅ Podcast can now be tested for mobile compatibility! "
                "The stereo mix will be downmixed to mono to simulate phone speakers."
            )
        
        # Try to copy the result JSON for additional info
        try:
            result_json = os.path.join(temp_dir, 'result.json')
            copy_from_env('/tmp/vlc_mono_result.json', result_json)
            
            with open(result_json, 'r') as f:
                result_data = json.load(f)
                metadata['export_result'] = result_data
                logger.info(f"Export result: {result_data}")
        except Exception as e:
            logger.warning(f"Could not read result JSON: {e}")
        
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)
        
    except Exception as e:
        shutil.rmtree(temp_dir, ignore_errors=True)
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "metadata": {}
        }
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "metadata": metadata
    }
