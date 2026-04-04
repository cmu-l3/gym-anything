#!/usr/bin/env python3
"""
Verifier for Configure Projector Output task.
Checks if VLC is properly configured to output at 1280x800 resolution.
"""

import json
import logging
import os
import sys
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

try:
    from vlc_verification_utils import parse_vlc_config
except ImportError as e:
    logging.error(f"Failed to import vlc_verification_utils: {e}")
    # Define a fallback parser
    def parse_vlc_config(filepath):
        """Fallback VLC config parser."""
        config = {}
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#') or line.startswith('['):
                        continue
                    if '=' in line:
                        key, value = line.split('=', 1)
                        config[key.strip()] = value.strip()
        except Exception as e:
            logging.error(f"Error parsing VLC config: {e}")
        return config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_projector_output_config(traj, env_info, task_info):
    """
    Verify VLC is configured for 1280x800 output.
    
    Args:
        traj: Trajectory information (not used in this verification)
        env_info: Environment info containing copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        Dict with passed (bool), score (float), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify configuration"
        }
    
    feedback_parts = []
    criteria_met = 0
    total_criteria = 4  # config exists, config valid, width correct, height correct
    
    # Target resolution
    target_width = 1280
    target_height = 800
    
    try:
        # Copy VLC config file from container
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc', mode='w+')
        temp_config.close()
        
        try:
            copy_from_env("/tmp/vlc_projector_config.vlcrc", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}")
            
            # Check if it's marked as missing
            temp_missing = tempfile.NamedTemporaryFile(delete=False, suffix='.missing')
            temp_missing.close()
            try:
                copy_from_env("/tmp/vlc_projector_config.missing", temp_missing.name)
                os.unlink(temp_missing.name)
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": "❌ VLC configuration file not found in container"
                }
            except:
                pass
            
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy VLC config: {str(e)}"
            }
        
        # Verify file exists and has content
        if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ VLC config file is empty or missing"
            }
        
        criteria_met += 1
        feedback_parts.append("✅ Config file exists")
        
        # Parse VLC configuration
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": 25,
                "feedback": "❌ VLC config file is empty or invalid | ✅ Config file exists"
            }
        
        criteria_met += 1
        feedback_parts.append(f"✅ Config valid ({len(config)} entries)")
        
        # Check for video output resolution settings
        # VLC uses various possible keys depending on output module and version
        width_keys = [
            'width', 'video-width', 'vout-width', 
            'qt-video-width', 'x11-display-width',
            'window-width', 'embedded-video-width'
        ]
        height_keys = [
            'height', 'video-height', 'vout-height',
            'qt-video-height', 'x11-display-height',
            'window-height', 'embedded-video-height'
        ]
        
        found_width = None
        found_height = None
        width_key_used = None
        height_key_used = None
        
        # Search for width setting
        for key in width_keys:
            if key in config:
                try:
                    found_width = int(config[key])
                    width_key_used = key
                    logger.info(f"Found width setting: {key}={found_width}")
                    break
                except (ValueError, TypeError):
                    logger.warning(f"Invalid width value for {key}: {config[key]}")
                    continue
        
        # Search for height setting
        for key in height_keys:
            if key in config:
                try:
                    found_height = int(config[key])
                    height_key_used = key
                    logger.info(f"Found height setting: {key}={found_height}")
                    break
                except (ValueError, TypeError):
                    logger.warning(f"Invalid height value for {key}: {config[key]}")
                    continue
        
        # Verify width
        if found_width is not None:
            if found_width == target_width:
                criteria_met += 1
                feedback_parts.append(f"✅ Width correct: {found_width} ({width_key_used})")
            else:
                feedback_parts.append(f"❌ Width incorrect: {found_width} (expected {target_width}, key: {width_key_used})")
        else:
            feedback_parts.append(f"❌ Width setting not found (expected {target_width})")
        
        # Verify height
        if found_height is not None:
            if found_height == target_height:
                criteria_met += 1
                feedback_parts.append(f"✅ Height correct: {found_height} ({height_key_used})")
            else:
                feedback_parts.append(f"❌ Height incorrect: {found_height} (expected {target_height}, key: {height_key_used})")
        else:
            feedback_parts.append(f"❌ Height setting not found (expected {target_height})")
        
        # Check for video output module (informational)
        if 'vout' in config:
            feedback_parts.append(f"ℹ️  Video output: {config['vout']}")
        
        # Clean up
        os.unlink(temp_config.name)
        
        # Calculate score and determine pass/fail
        score = int((criteria_met / total_criteria) * 100)
        
        # Success requires both width and height to be correct
        width_correct = (found_width == target_width)
        height_correct = (found_height == target_height)
        passed = width_correct and height_correct
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"✅ VLC configured for {target_width}x{target_height} | " + feedback
        else:
            if found_width is None and found_height is None:
                feedback = f"❌ No resolution settings found in config | " + feedback
            else:
                feedback = f"❌ Resolution not fully configured | " + feedback
        
        logger.info(f"Verification result: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification exception: {str(e)}"
        }
