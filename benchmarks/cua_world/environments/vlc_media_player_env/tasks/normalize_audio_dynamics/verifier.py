#!/usr/bin/env python3
"""
Verifier for Normalize Audio Dynamics task

Checks if VLC audio compressor is enabled with appropriate settings.
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


def parse_vlc_config(filepath):
    """
    Parse VLC configuration file (vlcrc).
    
    Returns:
        Dict with config key-value pairs
    """
    config = {}
    current_section = None
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Section headers [section_name]
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    continue
                
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                
                # Parse key=value
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Store both with and without section prefix
                    config[key] = value
                    if current_section:
                        config[f"{current_section}.{key}"] = value
        
        return config
    
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
        return {}


def check_compressor_enabled(config):
    """
    Check if audio compressor is enabled in VLC config.
    
    Args:
        config: Parsed VLC config dict
        
    Returns:
        (is_enabled, detail_message)
    """
    # Check audio-filter setting - this is the main indicator
    audio_filter = config.get('audio-filter', '')
    
    # Compressor can appear as:
    # - "compressor"
    # - "compressor:other_filter"
    # - "other_filter:compressor"
    if 'compressor' in audio_filter:
        return True, f"Compressor found in audio-filter: '{audio_filter}'"
    
    # Also check alternative keys where it might be set
    for key in ['core.audio-filter', 'audio-filters', 'audio-filter-list']:
        if key in config:
            value = config[key]
            if 'compressor' in value:
                return True, f"Compressor found in {key}: '{value}'"
    
    return False, f"Compressor not in audio-filter (current: '{audio_filter}')"


def check_compressor_parameters(config):
    """
    Check if compressor parameters are present and configured.
    
    Args:
        config: Parsed VLC config dict
        
    Returns:
        (params_found, detail_message)
    """
    # Look for compressor parameter keys
    compressor_keys = [
        'audio-compressor-attack',
        'audio-compressor-ratio', 
        'audio-compressor-threshold',
        'audio-compressor-release',
        'audio-compressor-rms-peak',
        'audio-compressor-knee',
        'audio-compressor-makeup-gain'
    ]
    
    found_params = {}
    for key in compressor_keys:
        # Check both with and without section prefix
        if key in config:
            found_params[key] = config[key]
        elif f"compressor.{key}" in config:
            found_params[key] = config[f"compressor.{key}"]
    
    if not found_params:
        return False, "No compressor parameters found in config"
    
    # Format message with first few parameters
    param_strs = [f"{k}={v}" for k, v in list(found_params.items())[:3]]
    msg = f"Found {len(found_params)} compressor parameters: {', '.join(param_strs)}"
    
    return True, msg


def verify_normalize_audio_dynamics(traj, env_info, task_info):
    """
    Verify normalize audio dynamics task completion.
    
    Checks:
    1. VLC config file is accessible
    2. Audio compressor is enabled in config
    3. Compressor parameters are present
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task info (unused)
        
    Returns:
        Dict with passed, score, and feedback
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
    
    # Create temp file for VLC config
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc', mode='w+b')
    temp_config.close()
    
    try:
        # Copy VLC config from container
        try:
            copy_from_env("/tmp/vlc_normalize_vlcrc", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Cannot access VLC config: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC config file is empty or not found"
            }
        
        # Parse config
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not parse VLC configuration file"
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ VLC config parsed ({len(config)} settings)")
        
        # Criterion 2: Check if compressor is enabled
        compressor_enabled, enable_msg = check_compressor_enabled(config)
        
        if compressor_enabled:
            criteria_met += 1
            feedback_parts.append(f"✅ {enable_msg}")
        else:
            feedback_parts.append(f"❌ {enable_msg}")
        
        # Criterion 3: Check if compressor parameters are present
        params_found, params_msg = check_compressor_parameters(config)
        
        if params_found:
            criteria_met += 1
            feedback_parts.append(f"✅ {params_msg}")
        else:
            feedback_parts.append(f"⚠️ {params_msg}")
        
        # Clean up temp file
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    # Calculate score
    # Primary criterion is compressor enabled (worth 60%)
    # Config accessible (20%)
    # Parameters present (20%)
    if compressor_enabled and criteria_met >= 2:
        score = int((criteria_met / total_criteria) * 100)
    else:
        # If compressor not enabled, cap score at 33%
        score = int((criteria_met / total_criteria) * 100)
        score = min(score, 33)
    
    passed = compressor_enabled and criteria_met >= 2
    
    # Add final verdict
    if passed:
        feedback_parts.append("✅ SUCCESS: Audio compressor properly configured")
        feedback_parts.append("The elderly user can now enjoy comfortable audio levels!")
    else:
        feedback_parts.append("❌ INCOMPLETE: Audio compressor needs to be enabled")
        if not compressor_enabled:
            feedback_parts.append("Hint: Tools → Effects → Audio Effects → Compressor → Enable")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
