#!/usr/bin/env python3
"""
Verifier for Adjust Stereo Balance task

Verifies that VLC has been configured to shift audio balance toward the right channel
for accessibility purposes (asymmetric hearing or damaged audio hardware).
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adjust_stereo_balance(traj, env_info, task_info):
    """
    Verify stereo balance adjustment task completion.

    Checks:
    1. Audio effects result file exists and is valid
    2. Audio filters/effects are enabled in VLC config
    3. Settings indicate audio balance modification (spatializer, headphone effects, etc.)

    VLC audio balance can be achieved through:
    - Spatializer effect (creates spatial audio effects)
    - Headphone effect (channel mixing)
    - Equalizer (frequency-based channel emphasis)
    - Custom audio filters

    Returns:
        dict: Verification results with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy balance result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_balance_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying balance result: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error copying balance result: {str(e)}"
            }

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Config file accessible
        config_exists = result.get('config_file_exists', False)
        if config_exists:
            criteria_met += 1
            feedback_parts.append("✅ VLC config accessible")
        else:
            feedback_parts.append("❌ VLC config not found")
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 0,
                "feedback": "VLC configuration file not found"
            }

        # Get audio effects from result
        audio_effects = result.get('audio_effects', {})
        effects_count = result.get('effects_count', 0)

        if not isinstance(audio_effects, dict):
            feedback_parts.append("⚠️ Audio effects data invalid")
            os.unlink(temp_result.name)
            return {
                "passed": False,
                "score": 33,
                "feedback": " | ".join(feedback_parts) + " | Invalid effects data"
            }

        # Criterion 2: Audio filters/effects are enabled
        audio_filter = audio_effects.get('audio-filter', '')
        
        # Check if any audio filters are enabled
        filters_enabled = False
        relevant_filters = ['spatializer', 'headphone', 'equalizer', 'compressor', 'param']
        
        if audio_filter:
            # Check if any relevant filter is in the audio-filter string
            for filter_name in relevant_filters:
                if filter_name in audio_filter.lower():
                    filters_enabled = True
                    break
        
        # Also check if any effect-specific settings exist
        if not filters_enabled and effects_count > 1:  # More than just audio-filter line
            # Check for specific effect settings
            for key in audio_effects.keys():
                for filter_name in relevant_filters:
                    if filter_name in key.lower():
                        filters_enabled = True
                        break
                if filters_enabled:
                    break

        if filters_enabled:
            criteria_met += 1
            feedback_parts.append(f"✅ Audio effects enabled ({effects_count} settings)")
        else:
            feedback_parts.append("❌ No audio effects/filters enabled")

        # Criterion 3: Verify balance-related modifications
        balance_indicators_found = []

        # Check for spatializer (spatial audio effects)
        spatializer_keys = [k for k in audio_effects.keys() if 'spatializer' in k.lower()]
        if spatializer_keys:
            balance_indicators_found.append("spatializer")

        # Check for headphone effect (channel mixing)
        headphone_keys = [k for k in audio_effects.keys() if 'headphone' in k.lower()]
        if headphone_keys:
            balance_indicators_found.append("headphone-effect")

        # Check for equalizer (frequency-based balance)
        equalizer_keys = [k for k in audio_effects.keys() if 'equalizer' in k.lower()]
        if equalizer_keys:
            balance_indicators_found.append("equalizer")

        # Check for compressor (dynamic range, can affect balance perception)
        compressor_keys = [k for k in audio_effects.keys() if 'compressor' in k.lower()]
        if compressor_keys:
            balance_indicators_found.append("compressor")

        # Check for parametric EQ
        param_eq_keys = [k for k in audio_effects.keys() if 'param-eq' in k.lower() or 'param_eq' in k.lower()]
        if param_eq_keys:
            balance_indicators_found.append("parametric-eq")

        # Verify that settings were modified (not just enabled but configured)
        settings_modified = effects_count > 1  # More than just enabling

        if balance_indicators_found and settings_modified:
            criteria_met += 1
            feedback_parts.append(
                f"✅ Audio balance modified (effects: {', '.join(balance_indicators_found)})"
            )
        elif balance_indicators_found:
            criteria_met += 0.5  # Partial credit
            feedback_parts.append(
                f"⚠️ Audio effects found but may not be fully configured ({', '.join(balance_indicators_found)})"
            )
        else:
            feedback_parts.append(
                "❌ No balance-related audio modifications detected"
            )

        # Log details for debugging
        if audio_filter:
            logger.info(f"Audio filter setting: {audio_filter}")
        logger.info(f"Total effects count: {effects_count}")
        logger.info(f"Balance indicators: {balance_indicators_found}")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error parsing balance result JSON: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading balance result: {str(e)}"
        }

    # Check completion marker (bonus indicator, not part of main criteria)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_balance_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }