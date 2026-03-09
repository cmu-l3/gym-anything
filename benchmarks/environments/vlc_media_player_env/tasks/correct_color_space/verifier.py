#!/usr/bin/env python3
"""
Verifier for Correct Color Space task
"""

import sys
import os
import logging
import tempfile

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    parse_vlc_config,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_float_safe(value_str, default=0.0):
    """Safely parse float from string."""
    try:
        return float(value_str)
    except (ValueError, TypeError):
        return default


def parse_int_safe(value_str, default=0):
    """Safely parse int from string."""
    try:
        return int(value_str)
    except (ValueError, TypeError):
        return default


def verify_color_correction_applied(config):
    """
    Verify that color correction settings were applied in VLC config.
    
    Args:
        config: Parsed VLC config dictionary
        
    Returns:
        Tuple of (success, score_contribution, feedback_list)
    """
    feedback_parts = []
    score_points = 0
    max_points = 4
    
    # Check if adjust filter is enabled in video-filter
    video_filter = config.get('video-filter', '')
    if 'adjust' in video_filter:
        score_points += 1
        feedback_parts.append("✅ Adjust filter enabled")
    else:
        feedback_parts.append("❌ Adjust filter not enabled (video-filter should contain 'adjust')")
        return False, 0, feedback_parts
    
    # Check gamma adjustment (should be increased from default 1.0)
    gamma_enabled = parse_int_safe(config.get('adjust-gamma', '0'))
    gamma_value = parse_float_safe(config.get('adjust-gamma-value', '1.0'), 1.0)
    
    if gamma_enabled == 1:
        if 1.15 <= gamma_value <= 2.0:
            score_points += 1
            feedback_parts.append(f"✅ Gamma corrected: {gamma_value:.2f} (good range)")
        else:
            feedback_parts.append(f"⚠️ Gamma value unusual: {gamma_value:.2f} (expected 1.15-2.0)")
    else:
        feedback_parts.append("❌ Gamma adjustment not enabled")
    
    # Check hue adjustment (should be shifted negative to remove green)
    hue_enabled = parse_int_safe(config.get('adjust-hue', '0'))
    hue_value = parse_float_safe(config.get('adjust-hue-value', '0'), 0.0)
    
    if hue_enabled == 1:
        if -60 <= hue_value <= -3:  # Negative hue shift to counteract green
            score_points += 1
            feedback_parts.append(f"✅ Hue corrected: {hue_value:.1f}° (removes green tint)")
        else:
            feedback_parts.append(f"⚠️ Hue value unexpected: {hue_value:.1f}° (expected -60 to -3)")
    else:
        feedback_parts.append("❌ Hue adjustment not enabled")
    
    # Check saturation (optional but helpful)
    saturation_enabled = parse_int_safe(config.get('adjust-saturation', '0'))
    saturation_value = parse_float_safe(config.get('adjust-saturation-value', '1.0'), 1.0)
    
    if saturation_enabled == 1:
        if 1.0 <= saturation_value <= 1.8:
            score_points += 1
            feedback_parts.append(f"✅ Saturation adjusted: {saturation_value:.2f}")
        else:
            # Partial credit if saturation is enabled but out of optimal range
            score_points += 0.5
            feedback_parts.append(f"⚠️ Saturation enabled but unusual: {saturation_value:.2f}")
    else:
        # Saturation is optional, give partial credit anyway if other corrections are good
        if score_points >= 2:
            score_points += 0.5
            feedback_parts.append("ℹ️ Saturation not adjusted (optional)")
    
    # Success if at least 2.5 points (adjust filter + gamma + hue minimum)
    success = score_points >= 2.5
    
    return success, score_points, feedback_parts


def verify_correct_color_space(traj, env_info, task_info):
    """
    Main verification function for correct_color_space@1 task.
    
    Args:
        traj: Trajectory data
        env_info: Environment info with copy_from_env function
        task_info: Task information
        
    Returns:
        dict with 'passed' (bool), 'score' (int), and 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    total_criteria = 4
    criteria_met = 0
    feedback_parts = []
    
    # Copy VLC config from container
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    temp_config.close()
    
    try:
        copy_from_env("/tmp/vlc_colorspace_config.txt", temp_config.name)
    except Exception as e:
        logger.error(f"Failed to copy VLC config: {e}", exc_info=True)
        return {
            'passed': False,
            'score': 0,
            'feedback': f"Failed to access VLC config file: {e}. Did VLC run and save settings?"
        }
    
    # Check if file exists and has content
    if not os.path.exists(temp_config.name) or os.path.getsize(temp_config.name) == 0:
        cleanup_verification_environment(os.path.dirname(temp_config.name))
        return {
            'passed': False,
            'score': 0,
            'feedback': "VLC config file not found or empty. Ensure VLC was launched and settings were saved."
        }
    
    # Parse config
    try:
        config = parse_vlc_config(temp_config.name)
    except Exception as e:
        logger.error(f"Failed to parse VLC config: {e}", exc_info=True)
        os.unlink(temp_config.name)
        return {
            'passed': False,
            'score': 0,
            'feedback': f"Failed to parse VLC config: {e}"
        }
    
    if not config:
        os.unlink(temp_config.name)
        return {
            'passed': False,
            'score': 0,
            'feedback': "VLC config file is empty or could not be parsed."
        }
    
    # Verify color corrections
    corrections_ok, score_points, correction_feedback = verify_color_correction_applied(config)
    
    # Add all correction feedback
    feedback_parts.extend(correction_feedback)
    
    # Calculate final score based on points earned
    criteria_met = score_points
    score = int((criteria_met / total_criteria) * 100)
    passed = corrections_ok and score >= 65
    
    # Check completion marker (optional, for logging)
    try:
        temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_marker.close()
        copy_from_env("/tmp/vlc_colorspace_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Optional: Check if snapshot was taken (indicates visual verification)
    try:
        temp_snapshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_snapshot.close()
        copy_from_env("/tmp/vlc_colorspace_snapshot.png", temp_snapshot.name)
        
        if os.path.exists(temp_snapshot.name) and os.path.getsize(temp_snapshot.name) > 5000:
            feedback_parts.append("✅ Snapshot taken (good practice for visual verification)")
        
        os.unlink(temp_snapshot.name)
    except Exception:
        pass  # Snapshot is optional
    
    # Cleanup
    os.unlink(temp_config.name)
    
    feedback = " | ".join(feedback_parts)
    
    return {
        'passed': passed,
        'score': score,
        'feedback': feedback
    }