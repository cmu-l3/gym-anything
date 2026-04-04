#!/usr/bin/env python3
"""
Verifier for Transpose Audio Pitch task
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


def parse_pitch_value(pitch_str, audio_filter):
    """
    Parse pitch value from various possible formats.
    
    VLC can store pitch as:
    - Semitones (e.g., "-3" or "-3.0")
    - Cents (e.g., "-300")
    - Ratio (e.g., "0.84" for -3 semitones)
    
    Returns pitch in semitones, or None if cannot parse.
    """
    if not pitch_str:
        return None
    
    try:
        # Clean the string
        pitch_str = pitch_str.strip().strip('"').strip("'")
        
        # Try to parse as float
        value = float(pitch_str)
        
        # Determine format based on magnitude
        if abs(value) > 20:
            # Likely in cents (e.g., -300 cents = -3 semitones)
            semitones = value / 100.0
            logger.info(f"Interpreted {value} cents as {semitones} semitones")
            return semitones
        elif 0.5 < abs(value) < 2.0 and value != 1.0:
            # Might be a ratio (e.g., 0.84 for -3 semitones)
            # Formula: semitones = 12 * log2(ratio)
            import math
            semitones = 12 * math.log2(value)
            logger.info(f"Interpreted ratio {value} as {semitones:.2f} semitones")
            return semitones
        else:
            # Assume it's already in semitones
            logger.info(f"Interpreted {value} as semitones directly")
            return value
            
    except (ValueError, TypeError) as e:
        logger.warning(f"Could not parse pitch value '{pitch_str}': {e}")
        return None


def verify_transpose_audio_pitch(traj, env_info, task_info):
    """
    Verify transpose audio pitch task completion.

    Checks:
    1. Audio effects result file exists and is valid
    2. Audio filter is enabled (scaletempo, pitch, or similar)
    3. Pitch shift is approximately -3 semitones (±0.5 tolerance)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy pitch result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_pitch_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying pitch result: {e}", exc_info=True)
            return {"passed": False, "score": 0.0, "feedback": f"Pitch result not found: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Pitch result accessible")

        # Get settings from result
        audio_filter = result.get('audio_filter', '')
        audio_filter_enabled = result.get('audio_filter_enabled', False)
        pitch_shift_str = result.get('pitch_shift', '')
        playback_rate = result.get('playback_rate', '')

        logger.info(f"Audio filter: {audio_filter}")
        logger.info(f"Pitch shift raw: {pitch_shift_str}")

        # Criterion 2: Check if audio filter is enabled
        if audio_filter_enabled or audio_filter:
            criteria_met += 1
            if audio_filter:
                feedback_parts.append(f"✅ Audio filter enabled: {audio_filter}")
            else:
                feedback_parts.append("✅ Audio filter enabled")
        else:
            feedback_parts.append("❌ Audio filter not enabled - effects may not be active")

        # Criterion 3: Check pitch shift value
        pitch_semitones = parse_pitch_value(pitch_shift_str, audio_filter)
        
        if pitch_semitones is not None:
            target = -3.0
            tolerance = 0.5
            
            if abs(pitch_semitones - target) <= tolerance:
                criteria_met += 1
                feedback_parts.append(f"✅ Pitch shift correct: {pitch_semitones:.2f} semitones (target: -3.0)")
            else:
                # Partial credit if at least some pitch shift is applied
                if pitch_semitones < 0:
                    criteria_met += 0.5
                    feedback_parts.append(f"⚠️ Pitch shifted but not at target: {pitch_semitones:.2f} semitones (expected -3.0 ± {tolerance})")
                else:
                    feedback_parts.append(f"❌ Wrong pitch direction: {pitch_semitones:.2f} semitones (expected negative)")
        else:
            feedback_parts.append("❌ Pitch shift value not found or invalid")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Invalid pitch result format: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Error verifying pitch: {str(e)}"}

    # Check completion marker (optional, not counted in score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_pitch_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    score = (criteria_met / total_criteria) * 100
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": round(score, 1),
        "feedback": feedback
    }