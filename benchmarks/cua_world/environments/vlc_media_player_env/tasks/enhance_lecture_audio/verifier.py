#!/usr/bin/env python3
"""
Verifier for Enhance Lecture Audio task

Checks if VLC equalizer has been configured to enhance lecture audio:
1. Equalizer is enabled
2. Low frequencies (bands 0-2: 60-310 Hz) are reduced
3. Mid-range speech frequencies (bands 4-6: 1-6 kHz) are boosted
"""

import sys
import os
import logging
import tempfile
import re
from typing import List, Tuple, Dict

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_vlc_equalizer_bands(vlcrc_content: str) -> List[float]:
    """
    Parse equalizer band values from vlcrc content.
    
    VLC stores bands as space-separated float values in dB.
    Format: equalizer-bands=<float> <float> ... (10 bands typically)
    
    Bands correspond to:
    0: 60Hz, 1: 170Hz, 2: 310Hz, 3: 600Hz, 4: 1kHz,
    5: 3kHz, 6: 6kHz, 7: 12kHz, 8: 14kHz, 9: 16kHz
    
    Args:
        vlcrc_content: Content of vlcrc file
        
    Returns:
        List of band values in dB, or empty list if not found
    """
    # Try multiple patterns for equalizer-bands
    patterns = [
        r'equalizer-bands\s*=\s*([^\n]+)',
        r'^equalizer-bands=([^\n]+)',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, vlcrc_content, re.MULTILINE)
        if match:
            bands_str = match.group(1).strip()
            try:
                bands = [float(x.strip()) for x in bands_str.split() if x.strip()]
                if bands:
                    logger.info(f"Parsed {len(bands)} equalizer bands: {bands}")
                    return bands
            except ValueError as e:
                logger.warning(f"Error parsing bands '{bands_str}': {e}")
                continue
    
    return []


def check_equalizer_enabled(vlcrc_content: str) -> bool:
    """
    Check if equalizer is enabled in VLC config.
    
    Args:
        vlcrc_content: Content of vlcrc file
        
    Returns:
        True if equalizer is enabled
    """
    # Multiple ways equalizer can be enabled
    enabled_patterns = [
        r'audio-filter\s*=.*equalizer',
        r'equalizer-preset\s*=\s*[^\n]+',
        r'equalizer-bands\s*=\s*[^\n]+',
        r'equalizer-preamp\s*=',
    ]
    
    for pattern in enabled_patterns:
        if re.search(pattern, vlcrc_content, re.IGNORECASE | re.MULTILINE):
            logger.info(f"Equalizer enabled (matched pattern: {pattern})")
            return True
    
    return False


def verify_enhance_lecture_audio(traj, env_info, task_info):
    """
    Verify that VLC equalizer has been configured to enhance lecture audio.
    
    Success criteria:
    1. Equalizer is enabled (30% of score)
    2. Low frequencies (bands 0-2) are reduced by ≥3 dB (35% of score)
    3. Mid-range speech frequencies (bands 4-6) are boosted by ≥3 dB (35% of score)
    
    Args:
        traj: Agent trajectory (not used)
        env_info: Environment info with copy_from_env function
        task_info: Task information (not used)
        
    Returns:
        Dict with passed (bool), score (int), feedback (str), and details (dict)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available",
            "details": {"error": "copy_function_missing"}
        }

    feedback_parts = []
    score = 0.0
    details = {}

    # Copy VLC config from container
    vlcrc_path = "/tmp/vlc_equalizer_vlcrc"
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='_vlcrc')

    try:
        copy_from_env(vlcrc_path, temp_config.name)

        with open(temp_config.name, 'r', encoding='utf-8', errors='ignore') as f:
            vlcrc_content = f.read()

        os.unlink(temp_config.name)

    except Exception as e:
        logger.error(f"Failed to read VLC configuration: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to read VLC configuration: {str(e)}",
            "details": {
                "error": "config_read_failed",
                "exception": str(e)
            }
        }

    # Criterion 1: Check if equalizer is enabled
    equalizer_enabled = check_equalizer_enabled(vlcrc_content)
    details["equalizer_enabled"] = equalizer_enabled

    if not equalizer_enabled:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Equalizer is not enabled. Please enable it via Tools → Effects and Filters → Audio Effects → Equalizer.",
            "details": {
                "equalizer_enabled": False,
                "bands_found": 0,
                "score_breakdown": {"enabled": 0.0, "low_reduced": 0.0, "mid_boosted": 0.0}
            }
        }

    feedback_parts.append("✅ Equalizer is enabled")
    score += 0.3
    details["score_enabled"] = 0.3

    # Criterion 2 & 3: Parse and verify band settings
    bands = parse_vlc_equalizer_bands(vlcrc_content)
    details["bands"] = [round(b, 2) for b in bands] if bands else []
    details["bands_count"] = len(bands)

    if len(bands) < 7:
        # Not enough bands configured
        feedback = " | ".join(feedback_parts)
        feedback += f" | ⚠️ Incomplete equalizer configuration: found {len(bands)} bands, expected at least 7"

        return {
            "passed": False,
            "score": int(score * 100),
            "feedback": feedback,
            "details": {
                **details,
                "bands_configured": len(bands),
                "score_breakdown": {
                    "enabled": 0.3,
                    "low_reduced": 0.0,
                    "mid_boosted": 0.0
                }
            }
        }

    # Check low-frequency reduction (bands 0-2: 60Hz, 170Hz, 310Hz)
    low_bands = bands[0:3]
    low_reduced_count = sum(1 for b in low_bands if b <= -2.5)  # At least -3 dB ideally, allow -2.5
    low_avg_reduction = sum(low_bands) / len(low_bands)

    details["low_bands"] = [round(b, 2) for b in low_bands]
    details["low_reduced_count"] = low_reduced_count
    details["low_avg_reduction"] = round(low_avg_reduction, 2)

    if low_reduced_count >= 2:
        # At least 2 out of 3 low bands are reduced
        score += 0.35
        feedback_parts.append(f"✅ Low frequencies reduced: {[f'{b:.1f}' for b in low_bands]} dB (rumble suppression)")
        details["low_freq_reduced"] = True
        details["score_low"] = 0.35
    elif low_reduced_count >= 1:
        # Partial credit: at least 1 band reduced
        partial_score = 0.15
        score += partial_score
        feedback_parts.append(f"⚠️ Low frequencies partially reduced: {[f'{b:.1f}' for b in low_bands]} dB (recommend -4 to -6 dB)")
        details["low_freq_reduced"] = "partial"
        details["score_low"] = partial_score
    else:
        feedback_parts.append(f"❌ Low frequencies not reduced: {[f'{b:.1f}' for b in low_bands]} dB (should be negative)")
        details["low_freq_reduced"] = False
        details["score_low"] = 0.0

    # Check mid-range frequency boost (bands 4-6: 1kHz, 3kHz, 6kHz)
    mid_bands = bands[4:7] if len(bands) >= 7 else bands[4:]
    mid_boosted_count = sum(1 for b in mid_bands if b >= 2.5)  # At least +3 dB ideally, allow +2.5
    mid_avg_boost = sum(mid_bands) / len(mid_bands)

    details["mid_bands"] = [round(b, 2) for b in mid_bands]
    details["mid_boosted_count"] = mid_boosted_count
    details["mid_avg_boost"] = round(mid_avg_boost, 2)

    if mid_boosted_count >= 2:
        # At least 2 out of 3 mid bands are boosted
        score += 0.35
        feedback_parts.append(f"✅ Mid-range frequencies boosted: {[f'{b:.1f}' for b in mid_bands]} dB (speech clarity enhanced)")
        details["mid_freq_boosted"] = True
        details["score_mid"] = 0.35
    elif mid_boosted_count >= 1:
        # Partial credit: at least 1 band boosted
        partial_score = 0.15
        score += partial_score
        feedback_parts.append(f"⚠️ Mid-range frequencies partially boosted: {[f'{b:.1f}' for b in mid_bands]} dB (recommend +4 to +6 dB)")
        details["mid_freq_boosted"] = "partial"
        details["score_mid"] = partial_score
    else:
        feedback_parts.append(f"❌ Mid-range frequencies not boosted: {[f'{b:.1f}' for b in mid_bands]} dB (should be positive)")
        details["mid_freq_boosted"] = False
        details["score_mid"] = 0.0

    # Summary feedback
    if score >= 0.95:
        feedback_parts.append("\n🎉 Excellent! The equalizer is optimally configured for lecture intelligibility.")
        feedback_parts.append("   Low-frequency rumble is suppressed and speech frequencies are well-enhanced.")
    elif score >= 0.75:
        feedback_parts.append("\n✅ Good work! Equalizer is properly configured with effective adjustments.")
    elif score >= 0.6:
        feedback_parts.append("\n⚠️ Equalizer is enabled but adjustments could be more aggressive.")
        feedback_parts.append("   Tip: Reduce 60-170Hz by -4 to -6 dB, boost 1-3kHz by +4 to +6 dB.")
    else:
        feedback_parts.append("\n❌ Equalizer needs significant adjustments to enhance speech clarity.")
        feedback_parts.append("   Strategy: Cut lows (rumble) and boost mids (speech intelligibility).")

    # Build score breakdown
    details["score_breakdown"] = {
        "enabled": details.get("score_enabled", 0.0),
        "low_reduced": details.get("score_low", 0.0),
        "mid_boosted": details.get("score_mid", 0.0),
        "total": score
    }

    details["final_score"] = score
    score_percent = int(score * 100)
    passed = score_percent >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score_percent,
        "feedback": feedback,
        "details": details
    }
