#!/usr/bin/env python3
"""
Verifier for Verify Display Calibration task
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


def parse_vlc_config_simple(filepath):
    """
    Simple VLC config parser for verification.
    
    Returns dict of key-value pairs from vlcrc file.
    """
    config = {}
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
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


def check_video_filters_disabled(config):
    """
    Check if video filters are disabled.
    
    Returns: (is_disabled, feedback)
    """
    video_filter = config.get('video-filter', '')
    vout_filter = config.get('vout-filter', '')
    
    # Check if filters are empty or disabled
    filters_disabled = True
    issues = []
    
    if video_filter and video_filter.strip():
        # Check if it's not just empty or whitespace
        if video_filter.strip() not in ['', 'none', 'disabled']:
            filters_disabled = False
            issues.append(f"video-filter={video_filter}")
    
    if vout_filter and vout_filter.strip():
        if vout_filter.strip() not in ['', 'none', 'disabled']:
            filters_disabled = False
            issues.append(f"vout-filter={vout_filter}")
    
    if filters_disabled:
        return True, "All video filters disabled"
    else:
        return False, f"Video filters still active: {', '.join(issues)}"


def check_adjustments_neutral(config, tolerance=0.06):
    """
    Check if video adjustments are at neutral values.
    
    Neutral values:
    - brightness: 1.0
    - contrast: 1.0
    - gamma: 1.0
    - saturation: 1.0
    - hue: 0
    
    Returns: (points_earned, max_points, feedback_list)
    """
    adjustments = {
        'brightness': (1.0, float(config.get('brightness', 1.0))),
        'contrast': (1.0, float(config.get('contrast', 1.0))),
        'gamma': (1.0, float(config.get('gamma', 1.0))),
        'saturation': (1.0, float(config.get('saturation', 1.0))),
    }
    
    points = 0
    max_points = len(adjustments)
    feedback = []
    
    for name, (expected, actual) in adjustments.items():
        if abs(actual - expected) <= tolerance:
            points += 1
            feedback.append(f"✓ {name}={actual:.2f}")
        else:
            feedback.append(f"✗ {name}={actual:.2f} (expected {expected:.2f})")
    
    # Check hue separately (expected to be 0, and config might not have it)
    hue = int(config.get('hue', 0))
    if abs(hue) <= 5:  # Allow small tolerance for hue
        feedback.append(f"✓ hue={hue}")
    else:
        feedback.append(f"✗ hue={hue} (expected 0)")
    
    return points, max_points, feedback


def verify_display_calibration(traj, env_info, task_info):
    """
    Verify display calibration task completion.
    
    Checks:
    1. VLC config file accessible
    2. Video filters disabled
    3. Video adjustments at neutral values
    4. Test pattern video was played
    5. Configuration persisted
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Scoring: total 7 points possible
    # - Config accessible: 1 point
    # - Filters disabled: 1 point
    # - Adjustments neutral: 4 points (one per adjustment)
    # - Video played: 1 point
    
    points_earned = 0
    max_points = 7
    feedback_parts = []
    
    # Copy VLC configuration file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        try:
            copy_from_env("/tmp/vlc_calibration_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error copying VLC config: {str(e)}"
            }
        
        # Criterion 1: Config file accessible
        points_earned += 1
        feedback_parts.append("✅ Config accessible")
        
        # Parse config file
        config = parse_vlc_config_simple(temp_config.name)
        
        if not config:
            return {
                "passed": False,
                "score": 14,  # 1/7 * 100
                "feedback": "VLC config file is empty or unreadable"
            }
        
        # Criterion 2: Check video filters are disabled
        filters_ok, filter_feedback = check_video_filters_disabled(config)
        
        if filters_ok:
            points_earned += 1
            feedback_parts.append(f"✅ {filter_feedback}")
        else:
            feedback_parts.append(f"❌ {filter_feedback}")
        
        # Criterion 3: Check adjustments are neutral (4 points possible)
        adj_points, adj_max, adj_feedback = check_adjustments_neutral(config)
        points_earned += adj_points
        
        if adj_points == adj_max:
            feedback_parts.append(f"✅ All adjustments neutral ({', '.join(adj_feedback)})")
        elif adj_points > 0:
            feedback_parts.append(f"⚠️ Some adjustments neutral ({adj_points}/{adj_max}): {', '.join(adj_feedback)}")
        else:
            feedback_parts.append(f"❌ Adjustments not neutral: {', '.join(adj_feedback)}")
        
        os.unlink(temp_config.name)
        
    except Exception as e:
        logger.error(f"Error verifying config: {e}", exc_info=True)
        try:
            os.unlink(temp_config.name)
        except:
            pass
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error verifying config: {str(e)}"
        }
    
    # Criterion 4: Check if test video was played
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json', mode='w+')
    
    try:
        try:
            copy_from_env("/tmp/vlc_calibration_result.json", temp_result.name)
            
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
            
            video_played = result.get('video_played', False)
            ml_found = result.get('media_library_found', False)
            
            # Grant point if video was played OR found in media library
            if video_played or ml_found:
                points_earned += 1
                feedback_parts.append("✅ Test pattern video played")
            else:
                feedback_parts.append("⚠️ Test pattern may not have been played")
            
            os.unlink(temp_result.name)
            
        except Exception as e:
            logger.warning(f"Could not verify video playback: {e}")
            feedback_parts.append("⚠️ Could not verify video playback")
            os.unlink(temp_result.name)
    
    except Exception as e:
        logger.warning(f"Error checking video playback: {e}")
    
    # Check completion marker (informational, not scored)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    try:
        copy_from_env("/tmp/vlc_calibration_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
        try:
            os.unlink(temp_marker.name)
        except:
            pass
    
    # Calculate score
    score = int((points_earned / max_points) * 100)
    passed = score >= 70  # Need at least 5/7 points (71%)
    
    feedback = " | ".join(feedback_parts)
    feedback += f" | Score: {points_earned}/{max_points} points"
    
    if passed:
        feedback += " | ✓ SUCCESS: VLC configured for accurate color display"
    else:
        feedback += " | ✗ FAILED: VLC not properly configured for calibration"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }