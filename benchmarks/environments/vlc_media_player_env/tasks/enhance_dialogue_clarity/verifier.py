#!/usr/bin/env python3
"""
Verifier for Enhance Dialogue Clarity task
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


def verify_enhance_dialogue_clarity(traj, env_info, task_info):
    """
    Verify enhance dialogue clarity task completion.

    Checks:
    1. VLC config file accessible
    2. Audio filters enabled (audio-filter key non-empty)
    3. Compressor active (in filter chain)
    4. Compressor configured properly (ratio ≥ 4.0)
    5. Normalization active
    6. Safe volume levels (not excessive)
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
        # Try to copy the config file
        try:
            copy_from_env("/tmp/vlc_dialogue_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying config file: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access VLC configuration: {str(e)}"
            }

        # Read the copied config
        with open(temp_config.name, 'r') as f:
            config_content = f.read()

        # Check if config is valid (not empty or error message)
        if not config_content or len(config_content) < 50 or "Config file missing" in config_content:
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC configuration file is empty or missing"
            }

        # Parse configuration
        config = parse_vlc_config(temp_config.name)
        
        if not config:
            os.unlink(temp_config.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not parse VLC configuration"
            }

        criteria_met += 1
        feedback_parts.append("✅ Config accessible")

        # Criterion 2: Audio filters enabled
        audio_filters = config.get('audio-filter', '').strip()
        
        if audio_filters:
            criteria_met += 1
            feedback_parts.append(f"✅ Audio filters enabled: {audio_filters}")
            
            # Criterion 3: Compressor active
            if 'compressor' in audio_filters.lower():
                criteria_met += 1
                feedback_parts.append("✅ Compressor active")
                
                # Criterion 4: Compressor configured properly
                compressor_ratio = config.get('compressor-ratio', '0')
                try:
                    ratio_value = float(compressor_ratio)
                    if ratio_value >= 4.0:
                        criteria_met += 1
                        feedback_parts.append(f"✅ Compressor ratio appropriate ({ratio_value}:1)")
                    else:
                        feedback_parts.append(f"⚠️ Compressor ratio low ({ratio_value}:1, recommend ≥4.0)")
                except (ValueError, TypeError):
                    # Check if compressor is in filter chain even without explicit ratio
                    # Some VLC versions might not expose ratio or use defaults
                    feedback_parts.append("~ Compressor enabled but ratio not set")
            else:
                feedback_parts.append("❌ Compressor not in audio filter chain")
            
            # Criterion 5: Normalization active
            # Check for various normalization-related filters
            normalization_keywords = ['normvol', 'norm', 'normalizer', 'volume-norm']
            has_normalization = any(keyword in audio_filters.lower() for keyword in normalization_keywords)
            
            # Also check for separate normalization config keys
            if not has_normalization:
                for key in config.keys():
                    if 'norm' in key.lower() or 'normaliz' in key.lower():
                        value = config.get(key, '')
                        if value and value != '0' and value.lower() not in ['false', 'no']:
                            has_normalization = True
                            break
            
            if has_normalization:
                criteria_met += 1
                feedback_parts.append("✅ Volume normalization active")
            else:
                feedback_parts.append("❌ Volume normalization not enabled")
        else:
            feedback_parts.append("❌ No audio filters enabled")

        # Criterion 6: Safe volume levels
        volume = config.get('audio-volume', '256')
        try:
            vol_value = int(volume)
            # VLC volume: 0-512, where 256 = 100%, 320 = 125%
            if vol_value <= 320:
                criteria_met += 1
                vol_percent = (vol_value / 256) * 100
                feedback_parts.append(f"✅ Safe volume level ({vol_value}/256 = {vol_percent:.0f}%)")
            else:
                vol_percent = (vol_value / 256) * 100
                feedback_parts.append(f"⚠️ Volume high ({vol_value}/256 = {vol_percent:.0f}%, may distort)")
        except (ValueError, TypeError):
            # If volume not set or invalid, give partial credit (not our main concern)
            criteria_met += 0.5
            feedback_parts.append("~ Volume setting not found (default assumed)")

        os.unlink(temp_config.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {str(e)}"
        }

    # Check completion marker (optional, for debugging)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_dialogue_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        if "completed" in marker_content.lower():
            feedback_parts.append("✓ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠ Completion marker not found")

    # Calculate score
    score = (criteria_met / total_criteria) * 100
    passed = score >= 67  # Need 4/6 criteria

    # Build feedback message
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    
    if passed:
        feedback += "\n\n✓ PASS: VLC configured for enhanced dialogue clarity"
    else:
        feedback += "\n\n✗ FAIL: Insufficient audio enhancements configured"
        feedback += "\n\nRequired: Enable Compressor (ratio ≥4.0) and Volume Normalization"

    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback
    }