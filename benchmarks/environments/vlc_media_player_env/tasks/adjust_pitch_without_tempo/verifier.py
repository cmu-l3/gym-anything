#!/usr/bin/env python3
"""
Verifier for Adjust Pitch Without Tempo task
"""

import sys
import os
import logging
import tempfile
import json
import math

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adjust_pitch_without_tempo(traj, env_info, task_info):
    """
    Verify adjust pitch without tempo task completion.

    Checks:
    1. Config file accessible and parseable
    2. Pitch adjustment filter is enabled
    3. Pitch shift value is approximately +1 semitone (+100 cents)
    4. Playback speed/tempo remains at 1.0x (unchanged)

    VLC can represent pitch shift in multiple ways:
    - Semitones: 1.0
    - Cents: 100.0
    - Frequency ratio: 1.059463 (2^(1/12))
    - Percentage: 105.9463
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Copy pitch adjustment result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_pitch_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying pitch result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying pitch result: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Config accessible")

        # Get pitch configuration
        pitch_config = result.get('pitch_config', {})
        
        if not isinstance(pitch_config, dict) or not pitch_config:
            os.unlink(temp_result.name)
            return {
                "passed": False, 
                "score": 25, 
                "feedback": "❌ No pitch configuration found. Please enable audio effects in VLC."
            }

        # Criterion 2: Check if audio filter chain includes pitch adjustment
        audio_filter = pitch_config.get('audio-filter', '')
        filter_enabled = False

        # VLC can use various filter names for pitch adjustment
        pitch_filter_names = ['scaletempo', 'pitch', 'scaletempo_pitch', 'audio_pitch']

        for filter_name in pitch_filter_names:
            if filter_name in audio_filter.lower():
                filter_enabled = True
                criteria_met += 1
                feedback_parts.append(f"✅ Pitch filter enabled: {filter_name}")
                break

        if not filter_enabled:
            feedback_parts.append(
                "❌ Pitch adjustment filter not enabled. "
                "Please enable the pitch shifter in Tools > Effects and Filters > Audio Effects."
            )

        # Criterion 3: Check pitch shift value is approximately +1 semitone
        pitch_value = None
        pitch_param_name = None
        pitch_correct = False

        # Look for pitch-related parameters
        pitch_params = ['pitch-shift', 'scaletempo-pitch', 'pitch-semitones']

        for param in pitch_params:
            if param in pitch_config and pitch_config[param]:
                pitch_value = pitch_config[param]
                pitch_param_name = param
                break

        if pitch_value is not None:
            try:
                val = float(pitch_value)

                # Expected frequency ratio for +1 semitone
                expected_ratio = 2 ** (1/12)  # ≈ 1.059463

                # Check different representations with tolerance
                if 0.8 <= val <= 1.2:  # Semitones representation
                    if 0.9 <= val <= 1.1:  # ±0.1 semitone tolerance
                        pitch_correct = True
                        criteria_met += 1
                        feedback_parts.append(f"✅ Pitch shift correct: {val} semitones")
                    else:
                        feedback_parts.append(f"⚠️ Pitch shift value: {val} semitones (expected: 1.0)")
                
                elif 80 <= val <= 120:  # Cents representation
                    if 90 <= val <= 110:  # ±10 cents tolerance
                        pitch_correct = True
                        criteria_met += 1
                        feedback_parts.append(f"✅ Pitch shift correct: {val} cents")
                    else:
                        feedback_parts.append(f"⚠️ Pitch shift value: {val} cents (expected: 100)")
                
                elif 1.04 <= val <= 1.08:  # Frequency ratio representation
                    if 1.049 <= val <= 1.069:  # ±1% tolerance
                        pitch_correct = True
                        criteria_met += 1
                        feedback_parts.append(f"✅ Pitch shift correct: {val:.4f} ratio")
                    else:
                        feedback_parts.append(f"⚠️ Pitch shift ratio: {val:.4f} (expected: {expected_ratio:.4f})")
                
                elif 104 <= val <= 108:  # Percentage representation
                    if 104.9 <= val <= 106.9:
                        pitch_correct = True
                        criteria_met += 1
                        feedback_parts.append(f"✅ Pitch shift correct: {val:.1f}%")
                    else:
                        feedback_parts.append(f"⚠️ Pitch shift percentage: {val:.1f}% (expected: ~105.9%)")
                
                else:
                    feedback_parts.append(
                        f"❌ Pitch shift value ({val}) is out of expected range. "
                        f"For +1 semitone, expected values are: 1.0 (semitones), "
                        f"100 (cents), or {expected_ratio:.4f} (frequency ratio)."
                    )

            except (ValueError, TypeError) as e:
                feedback_parts.append(f"❌ Could not parse pitch value: {pitch_value}")
        else:
            if filter_enabled:
                feedback_parts.append(
                    "❌ Pitch filter enabled but no pitch value set. "
                    "Please adjust the pitch shift slider to +1 semitone (+100 cents)."
                )
            else:
                feedback_parts.append("❌ No pitch adjustment value found")

        # Criterion 4: Verify playback speed is normal (1.0x)
        playback_rate = pitch_config.get('rate', '1.0')
        playback_speed = pitch_config.get('speed', '')

        tempo_preserved = True

        try:
            rate = float(playback_rate)
            if not (0.95 <= rate <= 1.05):  # Allow small tolerance
                tempo_preserved = False
                feedback_parts.append(
                    f"❌ Playback speed is {rate}x instead of normal (1.0x). "
                    f"Pitch adjustment should not change tempo."
                )
            else:
                criteria_met += 1
                feedback_parts.append(f"✅ Tempo preserved (rate: {rate}x)")
        except (ValueError, TypeError):
            # If can't parse, assume default of 1.0
            criteria_met += 1
            feedback_parts.append("✅ Tempo preserved (default)")

        # Check for conflicting speed adjustments
        if playback_speed:
            try:
                speed_val = float(playback_speed)
                if speed_val != 1.0 and speed_val != 0:
                    tempo_preserved = False
                    feedback_parts.append(
                        f"⚠️ Speed parameter set to {speed_val}, may affect tempo"
                    )
            except (ValueError, TypeError):
                pass

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading pitch result: {str(e)}"}

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_pitch_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    # Add helpful message if not passed
    if not passed:
        if not filter_enabled:
            feedback += " | 💡 Tip: Open Tools > Effects and Filters (Ctrl+E), go to Audio Effects tab, enable pitch adjustment"
        elif pitch_value is None:
            feedback += " | 💡 Tip: After enabling the filter, adjust the pitch shift slider to +1 semitone"
        elif not pitch_correct:
            feedback += " | 💡 Tip: Adjust pitch to +1 semitone (100 cents) for the correct transposition"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }


def main():
    """Standalone testing"""
    print("VLC Pitch Adjustment Verifier")
    print("=" * 60)
    print("This verifier checks if pitch is shifted by +1 semitone")
    print("without changing tempo/playback speed.")
    print("")

    # For testing, create a mock copy function
    def mock_copy(src, dst):
        print(f"Mock copy: {src} -> {dst}")
        # In real testing, this would actually copy files

    success, message = verify_adjust_pitch_without_tempo(
        traj=None,
        env_info={'copy_from_env': mock_copy},
        task_info={}
    )
    
    print(f"\nResult: {'✅ PASS' if success else '❌ FAIL'}")
    print(f"Message: {message}")
