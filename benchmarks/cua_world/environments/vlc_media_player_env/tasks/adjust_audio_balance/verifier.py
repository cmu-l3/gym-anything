#!/usr/bin/env python3
"""
Verifier for Adjust Audio Balance task

This verifier checks if the user successfully adjusted VLC's audio balance
to strongly favor the left channel (simulating a broken right earphone scenario).

Verification approach:
1. Parse VLC configuration file (vlcrc)
2. Look for multiple possible balance configuration keys
3. Verify balance value is between -0.7 and -1.0 (strongly left)
4. Check if audio effects are enabled
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


def parse_vlc_config_for_balance(config_path):
    """
    Parse VLC configuration file for audio balance settings.
    
    Returns:
        dict with 'balance', 'key', 'effects_enabled', and 'all_settings'
    """
    result = {
        'balance': None,
        'key': None,
        'effects_enabled': False,
        'all_settings': {}
    }
    
    try:
        with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        # Balance-related keys to search for (different VLC versions)
        balance_keys = [
            'audio-stereo-balance',
            'audio-channel-mixer-balance',
            'spatializer-balance',
            'stereo-widen-balance',
            'headphone-balance',
            'audio-balance',
        ]
        
        for line in lines:
            line = line.strip()
            
            # Skip comments and empty lines
            if not line or line.startswith('#') or line.startswith('['):
                continue
            
            # Parse key=value
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()
                
                result['all_settings'][key] = value
                
                # Check for balance keys
                if key in balance_keys:
                    try:
                        balance_float = float(value)
                        result['balance'] = balance_float
                        result['key'] = key
                        logger.info(f"Found balance setting: {key}={balance_float}")
                    except ValueError:
                        logger.warning(f"Invalid balance value for {key}: {value}")
                
                # Check for audio effects/filters enabled
                if key in ['audio-filter', 'audio-visual', 'spatializer', 'stereo-widen']:
                    if value and value != '0' and value.lower() != 'false':
                        result['effects_enabled'] = True
        
        return result
        
    except Exception as e:
        logger.error(f"Error parsing VLC config: {e}", exc_info=True)
        return result


def verify_adjust_audio_balance(traj, env_info, task_info):
    """
    Verify adjust audio balance task completion.

    Checks:
    1. VLC config file accessible and parseable
    2. Balance parameter found in config
    3. Balance value is in correct range (-0.7 to -1.0)
    4. Audio effects/filters are enabled (bonus criterion)

    Scoring:
    - 100%: All criteria met (balance correct, effects enabled, config valid)
    - 75%: Balance correct and persisted, effects may not be enabled
    - 50%: Balance adjusted but wrong range
    - 25%: Config accessible but no balance adjustment
    - 0%: No evidence of adjustment
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Copy balance result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        # First, try to get the JSON result
        try:
            copy_from_env("/tmp/vlc_balance_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying balance result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying balance result: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")

        # Extract values from JSON
        balance_value_str = result.get('balance_value', '0.0')
        balance_source = result.get('balance_source', 'unknown')
        balance_found = result.get('balance_found', False)
        effects_enabled = result.get('effects_enabled', False)

        logger.info(f"Balance result: value={balance_value_str}, source={balance_source}, found={balance_found}")

        # Parse balance value
        try:
            balance_value = float(balance_value_str)
        except (ValueError, TypeError):
            balance_value = 0.0
            logger.warning(f"Could not parse balance value: {balance_value_str}")

        # Additional verification: Parse vlcrc directly for robustness
        temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        vlcrc_parsed = None
        
        try:
            copy_from_env("/tmp/vlc_vlcrc_backup.txt", temp_vlcrc.name)
            vlcrc_parsed = parse_vlc_config_for_balance(temp_vlcrc.name)
            
            if vlcrc_parsed['balance'] is not None:
                # Use vlcrc value as authoritative source
                balance_value = vlcrc_parsed['balance']
                balance_source = vlcrc_parsed['key']
                balance_found = True
                logger.info(f"Verified balance from vlcrc: {balance_value} (key: {balance_source})")
            
            if vlcrc_parsed['effects_enabled']:
                effects_enabled = True
            
            os.unlink(temp_vlcrc.name)
        except Exception as e:
            logger.warning(f"Could not parse vlcrc backup: {e}")

        # Criterion 2: Balance parameter found
        if balance_found and balance_source not in ['default', 'unknown']:
            criteria_met += 1
            feedback_parts.append(f"✅ Balance parameter found ({balance_source})")
        else:
            feedback_parts.append("❌ No balance adjustment detected")

        # Criterion 3: Balance value in correct range (-0.7 to -1.0)
        TARGET_MIN = -1.0
        TARGET_MAX = -0.7
        
        if TARGET_MIN <= balance_value <= TARGET_MAX:
            criteria_met += 1
            feedback_parts.append(f"✅ Balance correct ({balance_value:.2f}, target: {TARGET_MAX} to {TARGET_MIN})")
        elif balance_value < 0 and balance_value > TARGET_MIN - 0.2:
            # Partial credit for being close
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Balance close but not in target range ({balance_value:.2f}, target: {TARGET_MAX} to {TARGET_MIN})")
        elif balance_value < 0:
            # At least moved to left
            criteria_met += 0.25
            feedback_parts.append(f"⚠️ Balance adjusted left but insufficient ({balance_value:.2f}, target: {TARGET_MAX} to {TARGET_MIN})")
        elif abs(balance_value - 0.0) < 0.01:
            # Still at default
            feedback_parts.append(f"❌ Balance unchanged (still at center: {balance_value:.2f})")
        else:
            # Moved to right (wrong direction!)
            feedback_parts.append(f"❌ Balance moved in wrong direction ({balance_value:.2f})")

        # Criterion 4: Audio effects enabled (bonus)
        if effects_enabled:
            criteria_met += 1
            feedback_parts.append("✅ Audio effects enabled")
        else:
            feedback_parts.append("⚠️ Audio effects may not be enabled")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading balance result: {str(e)}"}

    # Check completion marker (doesn't affect score, just informational)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_balance_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        logger.info(f"Completion marker: {marker_content}")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")

    # Calculate score (weighted)
    # Criterion 1: Config accessible (25%)
    # Criterion 2: Balance parameter found (25%)
    # Criterion 3: Balance value correct (40% - most important)
    # Criterion 4: Effects enabled (10% - bonus)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    feedback = " | ".join(feedback_parts)

    logger.info(f"Final score: {score}% (criteria met: {criteria_met}/{total_criteria})")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }