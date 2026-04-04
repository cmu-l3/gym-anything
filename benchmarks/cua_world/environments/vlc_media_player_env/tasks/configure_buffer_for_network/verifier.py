#!/usr/bin/env python3
"""
Verifier for Configure Buffer for Network task

Checks if VLC's file-caching has been increased from default (300ms)
to an appropriate value for network storage (3000-60000ms).
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path
from typing import Tuple, Dict, Optional

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_config(config_path: Path) -> Dict[str, str]:
    """
    Parse VLC configuration file into key-value dict
    
    Args:
        config_path: Path to vlcrc file
        
    Returns:
        Dict of config key-value pairs
    """
    config = {}
    
    if not config_path.exists():
        logger.warning(f"Config file not found: {config_path}")
        return config
    
    try:
        with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments, empty lines, and section headers
                if not line or line.startswith('#') or line.startswith('['):
                    continue
                
                # Parse key=value
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    
    except Exception as e:
        logger.error(f"Error parsing config file: {e}")
    
    return config


def verify_buffer_configuration(config_path: Path) -> Tuple[bool, str, Dict[str, any]]:
    """
    Verify that file-caching has been increased appropriately
    
    Args:
        config_path: Path to vlcrc file
        
    Returns:
        Tuple of (success, feedback_message, details_dict)
    """
    details = {
        'config_found': False,
        'file_caching_value': None,
        'file_caching_changed': False,
        'appropriate_value': False,
        'default_value': 300,
        'min_recommended': 3000,
        'max_reasonable': 60000
    }
    
    # Check if config file exists
    if not config_path.exists():
        return False, f"VLC config file not found: {config_path}", details
    
    details['config_found'] = True
    
    # Parse config
    config = parse_vlc_config(config_path)
    
    if 'file-caching' not in config:
        return False, "file-caching setting not found in vlcrc (still at default 300ms)", details
    
    # Get file-caching value
    try:
        file_caching = int(config['file-caching'])
    except (ValueError, TypeError) as e:
        return False, f"Invalid file-caching value: {config.get('file-caching', 'N/A')}", details
    
    details['file_caching_value'] = file_caching
    
    # Check if it's been changed from default 300
    DEFAULT_FILE_CACHING = 300
    if file_caching == DEFAULT_FILE_CACHING:
        return False, f"file-caching still at default value ({DEFAULT_FILE_CACHING}ms), needs to be increased for network storage", details
    
    details['file_caching_changed'] = True
    
    # Check if value is appropriate for network storage
    # For high-bitrate files on network storage, 3000ms+ is recommended
    MINIMUM_RECOMMENDED = 3000  # 3 seconds
    MAXIMUM_REASONABLE = 60000  # 60 seconds (more than this is excessive)
    
    if file_caching < MINIMUM_RECOMMENDED:
        return False, f"file-caching ({file_caching}ms) increased but still too low for network storage (minimum recommended: {MINIMUM_RECOMMENDED}ms)", details
    
    if file_caching > MAXIMUM_REASONABLE:
        return False, f"file-caching ({file_caching}ms) is excessively high (maximum reasonable: {MAXIMUM_REASONABLE}ms)", details
    
    details['appropriate_value'] = True
    
    # Success!
    return True, f"✓ file-caching correctly configured to {file_caching}ms (suitable for network storage)", details


def verify_configure_buffer_for_network(traj, env_info, task_info):
    """
    Main verification function called by gym-anything
    
    Args:
        traj: Trajectory data (not used in this verification)
        env_info: Environment info dict with copy_from_env function
        task_info: Task information dict
        
    Returns:
        Dict with keys: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available - cannot verify task"
        }
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy vlcrc file from container
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc', mode='w+')
    temp_vlcrc.close()
    
    try:
        # Try to copy the vlcrc file
        copy_from_env("/tmp/vlc_buffer_config.vlcrc", temp_vlcrc.name)
        logger.info(f"Copied vlcrc to {temp_vlcrc.name}")
    except Exception as e:
        logger.error(f"Error copying vlcrc: {e}", exc_info=True)
        
        # Try alternative location
        try:
            copy_from_env("/home/ga/.config/vlc/vlcrc", temp_vlcrc.name)
            logger.info("Copied vlcrc from alternative location")
        except Exception as e2:
            logger.error(f"Error copying from alternative location: {e2}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not access VLC config file: {str(e)}"
            }
    
    # Verify the buffer configuration
    vlcrc_path = Path(temp_vlcrc.name)
    success, message, details = verify_buffer_configuration(vlcrc_path)
    
    # Criterion 1: Config file found and parsed
    if details['config_found']:
        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")
    else:
        feedback_parts.append("❌ VLC config not found")
    
    # Criterion 2: file-caching value changed from default
    if details['file_caching_changed']:
        criteria_met += 1
        feedback_parts.append(f"✅ Cache changed from default ({details['file_caching_value']}ms)")
    elif details['file_caching_value'] is not None:
        feedback_parts.append(f"❌ Cache still at default ({details['file_caching_value']}ms)")
    else:
        feedback_parts.append("❌ Cache value not found")
    
    # Criterion 3: Value in appropriate range
    if details['appropriate_value']:
        criteria_met += 1
        feedback_parts.append(f"✅ Appropriate for network ({details['min_recommended']}-{details['max_reasonable']}ms)")
    elif details['file_caching_value'] is not None:
        if details['file_caching_value'] < details['min_recommended']:
            feedback_parts.append(f"⚠️ Too low for network (min: {details['min_recommended']}ms)")
        elif details['file_caching_value'] > details['max_reasonable']:
            feedback_parts.append(f"⚠️ Excessively high (max: {details['max_reasonable']}ms)")
    
    # Clean up temp file
    try:
        os.unlink(temp_vlcrc.name)
    except Exception as e:
        logger.warning(f"Could not delete temp file: {e}")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 65  # Pass if at least 2 out of 3 criteria met
    
    # Build detailed feedback
    feedback = " | ".join(feedback_parts)
    
    # Add detailed message
    if success:
        final_feedback = f"✅ PASSED: {message} | {feedback}"
    else:
        final_feedback = f"❌ FAILED: {message} | {feedback}"
    
    # Print detailed results for debugging
    print("\n" + "="*70)
    print("VLC Buffer Configuration Verification Results")
    print("="*70)
    print(f"Config found: {details['config_found']}")
    print(f"file-caching value: {details['file_caching_value']}ms" if details['file_caching_value'] is not None else "file-caching: Not set")
    print(f"Changed from default (300ms): {details['file_caching_changed']}")
    print(f"Appropriate for network: {details['appropriate_value']}")
    print(f"\nScore: {score}/100")
    print(f"Status: {'PASSED ✓' if passed else 'FAILED ✗'}")
    print(f"\nFeedback: {final_feedback}")
    print("="*70 + "\n")
    
    if not passed:
        print("💡 HINTS FOR SUCCESS:")
        print("  1. Open VLC and go to: Tools → Preferences (Ctrl+P)")
        print("  2. Click 'Show settings: All' button (bottom-left corner)")
        print("  3. Navigate to: Input / Codecs → Advanced")
        print("  4. Find 'File caching (ms)' and change to 3000 or higher")
        print("  5. Click 'Save' and restart VLC")
        print("\n  Alternative: Edit ~/.config/vlc/vlcrc and set: file-caching=3000")
        print("="*70 + "\n")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }
