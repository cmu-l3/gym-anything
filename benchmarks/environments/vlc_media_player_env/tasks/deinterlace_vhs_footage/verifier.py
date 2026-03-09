#!/usr/bin/env python3
"""
Verifier for Deinterlace VHS Footage task

Checks that VLC has been configured to enable deinterlacing
for an interlaced video file.
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


def parse_vlc_config(config_path):
    """
    Parse VLC configuration file (vlcrc).
    
    Args:
        config_path: Path to vlcrc file
        
    Returns:
        Dict of config key-value pairs
    """
    config = {}
    try:
        with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments, empty lines, and section headers
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                
                # Parse key=value pairs
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}")
    
    return config


def check_deinterlace_enabled(config):
    """
    Check if deinterlacing is enabled in VLC config.
    
    Returns:
        (enabled: bool, mode: str or None, method: str)
    """
    # Valid deinterlace modes
    valid_modes = [
        'blend', 'bob', 'discard', 'linear', 'mean', 
        'phosphor', 'x', 'yadif', 'yadif2x', 'ivtc'
    ]
    
    enabled = False
    mode = None
    detection_method = None
    
    # Method 1: Check deinterlace flag
    if 'deinterlace' in config:
        deinterlace_value = config['deinterlace'].strip('"').strip("'")
        if deinterlace_value in ['1', 'true', 'yes', 'on']:
            enabled = True
            detection_method = 'deinterlace flag'
            logger.info(f"Deinterlace enabled via flag: {deinterlace_value}")
    
    # Method 2: Check deinterlace-mode setting
    if 'deinterlace-mode' in config:
        mode_value = config['deinterlace-mode'].strip('"').strip("'").lower()
        if mode_value in valid_modes:
            enabled = True
            mode = mode_value
            detection_method = 'deinterlace-mode'
            logger.info(f"Deinterlace mode set: {mode}")
    
    # Method 3: Check video-filter chain for deinterlace
    if 'video-filter' in config:
        video_filters = config['video-filter'].lower()
        if 'deinterlace' in video_filters:
            enabled = True
            detection_method = 'video-filter chain'
            logger.info(f"Deinterlace in video filter: {video_filters}")
    
    # Method 4: Check sout-deinterlace-mode (streaming output deinterlace)
    if 'sout-deinterlace-mode' in config:
        sout_mode = config['sout-deinterlace-mode'].strip('"').strip("'").lower()
        if sout_mode in valid_modes:
            enabled = True
            mode = sout_mode
            detection_method = 'sout-deinterlace-mode'
            logger.info(f"Deinterlace via sout mode: {sout_mode}")
    
    # Method 5: Check for deinterlace filter specifically enabled
    if 'deinterlace-filter' in config or 'deinterlace-enabled' in config:
        enabled = True
        detection_method = 'deinterlace filter flag'
    
    return enabled, mode, detection_method


def verify_deinterlace_vhs_footage(traj, env_info, task_info):
    """
    Verify deinterlace VHS footage task completion.
    
    Checks:
    1. VLC config file is accessible
    2. Deinterlacing is enabled
    3. A valid deinterlace mode is set (if applicable)
    
    Args:
        traj: Trajectory data (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        Dict with passed, score, feedback, and metadata
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    metadata = {}
    
    # Criterion 1: VLC config file exists and is accessible
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_deinterlace_config.txt", temp_config.name)
        
        if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC configuration file not found or empty. Did VLC save settings?",
                "metadata": {"config_found": False}
            }
        
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
        metadata['config_found'] = True
        
    except Exception as e:
        logger.error(f"Error copying config: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to access VLC configuration: {str(e)}",
            "metadata": {"error": str(e)}
        }
    
    # Parse the configuration
    config = parse_vlc_config(temp_config.name)
    metadata['config_keys'] = list(config.keys())
    
    if not config:
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 33,
            "feedback": "❌ VLC config is empty or could not be parsed",
            "metadata": metadata
        }
    
    # Criterion 2: Check if deinterlacing is enabled
    enabled, mode, detection_method = check_deinterlace_enabled(config)
    
    metadata['deinterlace_enabled'] = enabled
    metadata['deinterlace_mode'] = mode
    metadata['detection_method'] = detection_method
    
    if not enabled:
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 33,
            "feedback": (
                "❌ Deinterlacing is NOT enabled in VLC configuration.\n"
                "Expected to find one of:\n"
                "  - 'deinterlace=1'\n"
                "  - 'deinterlace-mode' set to a valid algorithm\n"
                "  - 'deinterlace' in video-filter chain\n"
                "\n"
                "💡 Tip: Use Video → Deinterlace menu or Tools → Preferences → Video → Filters"
            ),
            "metadata": metadata
        }
    
    criteria_met += 1
    feedback_parts.append(f"✅ Deinterlacing enabled (via {detection_method})")
    
    # Criterion 3: Check if a valid deinterlace mode is set
    if mode:
        criteria_met += 1
        feedback_parts.append(f"✅ Deinterlace mode: {mode}")
    else:
        # Deinterlacing is enabled but mode not explicitly set
        # This is still acceptable - give partial credit
        criteria_met += 0.5
        feedback_parts.append("⚠️ Deinterlacing enabled but specific mode not detected (still acceptable)")
    
    # Check completion marker (bonus feedback)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_deinterlace_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Cleanup
    os.unlink(temp_config.name)
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback message
    if passed:
        feedback_message = (
            "🎉 SUCCESS! Deinterlacing has been properly configured.\n" +
            " | ".join(feedback_parts) +
            "\n\nThe VHS footage will now play smoothly without interlacing artifacts. "
            "Great job helping preserve those family memories! 📺"
        )
    else:
        feedback_message = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_message,
        "metadata": metadata
    }


# Entry point for gym-anything
def verify(submission_dir: str):
    """
    Alternative entry point that accepts submission directory.
    For compatibility with different calling conventions.
    """
    # This would need to be adapted based on actual gym-anything interface
    # For now, keeping the main entry point as verify_deinterlace_vhs_footage
    pass
