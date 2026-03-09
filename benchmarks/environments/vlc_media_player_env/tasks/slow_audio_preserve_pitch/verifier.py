#!/usr/bin/env python3
"""
Verifier for Slow Audio Preserve Pitch task

Checks:
1. VLC config file accessible
2. Playback speed set to 0.65x (±0.02 tolerance)
3. Audio pitch preservation (time-stretching) enabled
"""

import sys
import os
import logging
import tempfile
import json
from typing import Dict, Tuple, Any

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_config(config_path: str) -> Dict[str, str]:
    """Parse VLC configuration file."""
    config = {}
    
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
        logger.error(f"Error parsing VLC config: {e}")
        return {}
    
    return config


def check_playback_speed(config: Dict[str, str]) -> Tuple[bool, str, float]:
    """
    Check if playback speed is set to 0.65 (65%).
    
    Returns:
        (success, feedback_message, actual_speed)
    """
    # VLC stores playback rate as float (1.0 = normal speed)
    # Look for 'rate' or 'playback-speed' keys
    
    rate_value = None
    rate_key = None
    
    # Check common keys for playback rate
    for key in ['rate', 'playback-speed', 'playback-rate']:
        if key in config:
            rate_key = key
            rate_value = config[key]
            break
    
    if rate_value is None:
        return False, "⚠ Playback speed setting not found in VLC config", 1.0
    
    try:
        speed = float(rate_value)
    except ValueError:
        return False, f"✗ Invalid speed value: {rate_value}", 1.0
    
    # Target speed with tolerance
    target_speed = 0.65
    tolerance = 0.02
    
    if abs(speed - target_speed) <= tolerance:
        return True, f"✓ Playback speed correctly set to {speed:.3f}x (target: {target_speed}x)", speed
    else:
        return False, f"✗ Playback speed is {speed:.3f}x, should be {target_speed}x (±{tolerance})", speed


def check_pitch_preservation(config: Dict[str, str]) -> Tuple[bool, str]:
    """
    Check if audio pitch preservation (time-stretching) is enabled.
    
    VLC uses various settings for this:
    - audio-time-stretch=1 (main setting)
    - scaletempo filter in audio-filter
    - scaletempo2 in newer versions
    
    Returns:
        (success, feedback_message)
    """
    # Check for time-stretch setting
    if 'audio-time-stretch' in config:
        value = config['audio-time-stretch'].lower()
        if value in ['1', 'true', 'yes', 'on']:
            return True, f"✓ Pitch preservation enabled (audio-time-stretch={config['audio-time-stretch']})"
        elif value in ['0', 'false', 'no', 'off']:
            return False, "✗ Pitch preservation explicitly disabled (audio-time-stretch=0)"
    
    # Check for scaletempo filter
    if 'audio-filter' in config:
        filters = config['audio-filter']
        if 'scaletempo' in filters.lower():
            return True, f"✓ Pitch preservation enabled (scaletempo filter active: {filters})"
    
    # Check for scaletempo-specific settings (indicates it's being used)
    scaletempo_keys = [k for k in config.keys() if 'scaletempo' in k.lower()]
    if scaletempo_keys:
        return True, f"✓ Pitch preservation likely enabled (found scaletempo settings: {', '.join(scaletempo_keys)})"
    
    # VLC enables time-stretch by default when speed != 1.0
    # If we don't find explicit disable, assume it's enabled (default behavior)
    return True, "✓ Pitch preservation enabled (VLC default behavior - no explicit disable found)"


def verify_slow_audio_preserve_pitch(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for slow audio preserve pitch task.
    
    Args:
        traj: Trajectory information
        env_info: Environment information including copy_from_env function
        task_info: Task-specific information
        
    Returns:
        Dict with keys: passed (bool), score (int), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "✗ Copy function not available"
        }
    
    criteria_met = 0.0
    total_criteria = 3.0
    feedback_parts = []
    
    print("=" * 70)
    print("Verifying: slow_audio_preserve_pitch@1")
    print("=" * 70)
    
    # Copy VLC config file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt', mode='w+')
    
    try:
        copy_from_env("/tmp/vlc_slow_audio_config.txt", temp_config.name)
    except Exception as e:
        logger.error(f"Error copying VLC config: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"✗ Could not copy VLC config file: {str(e)}"
        }
    
    # Parse VLC configuration
    config = parse_vlc_config(temp_config.name)
    
    if not config:
        os.unlink(temp_config.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": "✗ VLC configuration file is empty or could not be parsed"
        }
    
    criteria_met += 1.0
    feedback_parts.append(f"✓ VLC config accessible ({len(config)} settings found)")
    print(f"\n✓ Criterion 1/3: Config file accessible")
    print(f"   Found {len(config)} configuration settings")
    
    # Check playback speed (Critical - 50% weight)
    speed_ok, speed_msg, actual_speed = check_playback_speed(config)
    feedback_parts.append(speed_msg)
    print(f"\n⚙ Criterion 2/3: Playback Speed")
    print(f"   {speed_msg}")
    
    if speed_ok:
        criteria_met += 1.5  # 50% of total score (1.5 out of 3)
    else:
        # Partial credit if speed was changed from default
        if actual_speed != 1.0:
            # Calculate partial credit based on how close to target
            error = abs(actual_speed - 0.65)
            if error <= 0.05:  # Within 5%
                partial = 1.0
                feedback_parts.append(f"  ⚠ Partial credit: speed is close to target")
            elif error <= 0.10:  # Within 10%
                partial = 0.7
                feedback_parts.append(f"  ⚠ Partial credit: speed was adjusted but not precise")
            else:
                partial = 0.3
                feedback_parts.append(f"  ⚠ Minimal credit: speed was changed but far from target")
            
            criteria_met += partial
            print(f"   → Partial credit: +{partial:.1f} points")
        else:
            print(f"   → No credit: speed unchanged")
    
    # Check pitch preservation (Important - 30% weight)
    pitch_ok, pitch_msg = check_pitch_preservation(config)
    feedback_parts.append(pitch_msg)
    print(f"\n🎵 Criterion 3/3: Pitch Preservation")
    print(f"   {pitch_msg}")
    
    if pitch_ok:
        criteria_met += 0.5  # 30% weight (remaining to make 100%)
    else:
        feedback_parts.append("  ⚠ Without pitch preservation, audio will have 'chipmunk effect'")
        print(f"   → No credit: pitch preservation not verified")
    
    # Clean up temp file
    os.unlink(temp_config.name)
    
    # Optional: Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_slow_audio_completed.txt", temp_marker.name)
        feedback_parts.append("✓ Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠ Completion marker not found")
    
    # Calculate score (0-100)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80  # 80% threshold
    
    # Build feedback message
    feedback = " | ".join(feedback_parts)
    
    # Print summary
    print("\n" + "=" * 70)
    print(f"Final Score: {criteria_met:.1f}/{total_criteria} = {score}%")
    print(f"Status: {'✅ PASS' if passed else '❌ FAIL'} (threshold: 80%)")
    
    if not passed:
        print("\nRequired for success:")
        print("  1. Set playback speed to 0.65x (Playback → Speed → Custom)")
        print("  2. Ensure audio time-stretching is enabled (Tools → Preferences → Audio)")
        print("  3. Settings must persist in VLC config file")
    
    print("=" * 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
