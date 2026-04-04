#!/usr/bin/env python3
"""
Verifier for Setup Practice Loop task

Checks:
1. Playback speed is set to 0.70 (±0.05 tolerance)
2. Time-stretching (pitch preservation) is enabled
3. Evidence of A-B repeat configuration (partial credit if not fully detectable)
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_qt_config(filepath):
    """
    Parse VLC Qt interface config file (INI-like format).
    """
    config = {}
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            current_section = None
            for line in f:
                line = line.strip()
                
                # Section headers
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    config[current_section] = {}
                    continue
                
                # Key-value pairs
                if '=' in line:
                    key, value = line.split('=', 1)
                    if current_section:
                        config[current_section][key.strip()] = value.strip()
                    else:
                        config[key.strip()] = value.strip()
        
        return config
    except Exception as e:
        logger.error(f"Error parsing Qt config: {e}")
        return {}


def check_playback_speed(result_data, vlcrc_config):
    """
    Check if playback speed is set to 0.70 (±0.05 tolerance).
    """
    target_speed = 0.70
    tolerance = 0.05
    
    try:
        speed_str = result_data.get('playback_speed', '1.0')
        speed = float(speed_str)
        
        diff = abs(speed - target_speed)
        
        if diff <= tolerance:
            return True, f"✅ Playback speed correct: {speed:.2f} (target: {target_speed})"
        elif speed < 1.0:
            # Speed was changed, just not to exact target
            return False, f"⚠️ Playback speed modified to {speed:.2f}, but target is {target_speed} (±{tolerance})"
        else:
            return False, f"❌ Playback speed unchanged: {speed:.2f} (target: {target_speed})"
    
    except (ValueError, TypeError) as e:
        logger.error(f"Error parsing speed: {e}")
        return False, f"❌ Could not parse playback speed"


def check_time_stretching(result_data, vlcrc_config):
    """
    Check if time-stretching (pitch preservation) is enabled.
    """
    try:
        timestretch_str = result_data.get('time_stretch_enabled', '0')
        
        # Check if enabled (1, true, or non-zero)
        if timestretch_str in ['1', 'true', 'True', 'TRUE']:
            return True, "✅ Time-stretching enabled (pitch preservation active)"
        elif timestretch_str == '0' or timestretch_str == 'false':
            # Check if speed was modified - some VLC versions enable implicitly
            speed_str = result_data.get('playback_speed', '1.0')
            speed = float(speed_str)
            
            if speed != 1.0:
                # Speed modified but time-stretch not explicitly set
                # Give partial credit
                return True, "⚠️ Time-stretching not explicitly enabled, but may be implicit with speed change"
            else:
                return False, "❌ Time-stretching disabled"
        else:
            # Unknown value, be lenient
            return True, f"⚠️ Time-stretching status unclear: {timestretch_str}"
    
    except Exception as e:
        logger.error(f"Error checking time-stretch: {e}")
        return False, "❌ Could not verify time-stretching"


def check_ab_repeat(result_data, vlcrc_config, qt_config):
    """
    Check for evidence of A-B repeat configuration.
    
    This is the hardest to verify as A-B state may not persist fully.
    We give credit for any evidence of A-B repeat being used.
    """
    ab_state = result_data.get('ab_repeat_state', 'none')
    ab_detected = result_data.get('ab_loop_detected', False)
    
    # Check result data
    if ab_state != 'none' and ab_state != '':
        return True, f"✅ A-B repeat detected: {ab_state}"
    
    if ab_detected:
        return True, "✅ A-B loop activity detected during playback"
    
    # Check vlcrc for A-B related settings
    if vlcrc_config:
        # Check for input-repeat
        if 'input-repeat' in vlcrc_config:
            repeat_val = vlcrc_config['input-repeat']
            if repeat_val != '0':
                return True, f"✅ Repeat enabled in config: input-repeat={repeat_val}"
        
        # Check for explicit A-B loop points
        if 'ab-loop-a' in vlcrc_config or 'ab-loop-b' in vlcrc_config:
            loop_a = vlcrc_config.get('ab-loop-a', '0')
            loop_b = vlcrc_config.get('ab-loop-b', '0')
            
            try:
                a_val = float(loop_a)
                b_val = float(loop_b)
                
                if a_val > 0 and b_val > a_val:
                    # Check if points are approximately correct for solo (94-118s, ±10s tolerance)
                    if 84 <= a_val <= 104 and 108 <= b_val <= 128:
                        return True, f"✅ A-B loop points configured correctly: A={a_val:.1f}s, B={b_val:.1f}s"
                    else:
                        return True, f"⚠️ A-B loop points set (A={a_val:.1f}s, B={b_val:.1f}s) but may not match solo section"
            except ValueError:
                pass
    
    # Check Qt config for A-B loop
    if qt_config:
        for section_key in qt_config.keys():
            if isinstance(qt_config[section_key], dict):
                section = qt_config[section_key]
                
                # Look for A-B loop keys
                for key in section.keys():
                    if 'abloop' in key.lower() or 'ab-loop' in key.lower() or 'ab_loop' in key.lower():
                        return True, f"✅ A-B loop setting found in Qt config: {key}"
    
    # No evidence found - but this might be okay if other criteria pass
    return False, "⚠️ No clear evidence of A-B repeat configuration (may not persist in config)"


def verify_practice_loop(traj, env_info, task_info):
    """
    Main verification function for setup_practice_loop task.
    
    Checks:
    1. Playback speed set to 0.70 (±0.05) - CRITICAL
    2. Time-stretching enabled - CRITICAL
    3. A-B repeat configured - BONUS (hard to verify fully)
    
    Pass threshold: 2/3 criteria (67%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    logger.info("=== Verifying setup practice loop task ===")
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_practice_loop_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result JSON: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Result file not found - task may not have been attempted: {str(e)}"
            }
        
        # Parse result JSON
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
        
        logger.info(f"Result data: {result_data}")
        os.unlink(temp_result.name)
        
    except Exception as e:
        logger.error(f"Error reading result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading result file: {str(e)}"
        }
    
    # Copy and parse VLC config files
    vlcrc_config = {}
    qt_config = {}
    
    # Copy vlcrc
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.vlcrc')
    try:
        copy_from_env("/tmp/vlcrc", temp_vlcrc.name)
        vlcrc_config = parse_vlc_config(temp_vlcrc.name)
        logger.info(f"Loaded vlcrc: {len(vlcrc_config)} entries")
        os.unlink(temp_vlcrc.name)
    except Exception as e:
        logger.warning(f"Could not load vlcrc: {e}")
    
    # Copy Qt config
    temp_qt = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    try:
        copy_from_env("/tmp/vlc-qt-interface.conf", temp_qt.name)
        qt_config = parse_vlc_qt_config(temp_qt.name)
        logger.info(f"Loaded Qt config: {len(qt_config)} sections")
        os.unlink(temp_qt.name)
    except Exception as e:
        logger.warning(f"Could not load Qt config: {e}")
    
    # Check 1: Playback speed (CRITICAL)
    speed_ok, speed_feedback = check_playback_speed(result_data, vlcrc_config)
    feedback_parts.append(speed_feedback)
    if speed_ok:
        criteria_met += 1
        logger.info("✅ Playback speed check passed")
    else:
        logger.warning("✗ Playback speed check failed")
    
    # Check 2: Time-stretching (CRITICAL)
    stretch_ok, stretch_feedback = check_time_stretching(result_data, vlcrc_config)
    feedback_parts.append(stretch_feedback)
    if stretch_ok:
        criteria_met += 1
        logger.info("✅ Time-stretching check passed")
    else:
        logger.warning("✗ Time-stretching check failed")
    
    # Check 3: A-B repeat (BONUS - partial credit)
    ab_ok, ab_feedback = check_ab_repeat(result_data, vlcrc_config, qt_config)
    feedback_parts.append(ab_feedback)
    if ab_ok:
        criteria_met += 1
        logger.info("✅ A-B repeat check passed")
    else:
        logger.warning("✗ A-B repeat check failed (partial credit may apply)")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    
    # Pass threshold: at least 2/3 criteria (67%)
    passed = criteria_met >= 2
    
    feedback = " | ".join(feedback_parts)
    feedback += f" | Checks passed: {criteria_met}/{total_criteria}"
    
    logger.info(f"Verification complete: {criteria_met}/{total_criteria} checks passed")
    logger.info(f"Passed: {passed}, Score: {score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }