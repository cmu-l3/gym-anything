#!/usr/bin/env python3
"""
Verifier for Practice Music Transcription task

Verifies that VLC is configured for music transcription practice:
- Playback speed set to ~0.60x (60%)
- Time-stretching filter enabled (preserves pitch)
- Settings persisted to configuration

This allows musicians to slow down complex passages for note-by-note learning
without the distorted "chipmunk" effect of pitch-shifted audio.
"""

import sys
import os
import logging
import tempfile
import json

# Use relative path to utils folder (verifier runs on host)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_practice_music_transcription(traj, env_info, task_info):
    """
    Verify practice music transcription task completion.
    
    Checks:
    1. Playback speed configured to 0.60x (±0.05 tolerance)
    2. Time-stretching filter enabled (scaletempo or equivalent)
    3. Configuration persisted to VLC config file
    4. Pitch preservation verified (not just rate change)
    5. Speed is practically usable (0.4-0.8 range)
    
    Pass threshold: 75% (4/5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Copy transcription result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        try:
            copy_from_env("/tmp/vlc_transcription_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying transcription result: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Error copying transcription result: {str(e)}"
            }
        
        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        logger.info(f"Transcription result: {result}")
        
        # Extract values
        speed = float(result.get('speed', 1.0))
        time_stretch_enabled = result.get('time_stretch_enabled', False)
        audio_filter = result.get('audio_filter', '')
        config_found = result.get('config_found', False)
        source = result.get('source', 'unknown')
        
        speed_percent = speed * 100
        
        feedback_parts.append(f"Speed: {speed:.2f}x ({speed_percent:.0f}%)")
        
        # Criterion 1: Speed configured to ~0.60x (±0.05 tolerance)
        target_speed = 0.60
        speed_tolerance = 0.05
        
        if abs(speed - target_speed) <= speed_tolerance:
            criteria_met += 1
            feedback_parts.append(f"✅ Speed at target ({target_speed:.2f}x ± {speed_tolerance:.2f})")
        elif 0.4 <= speed < 0.55:
            # Partial credit: speed changed but too slow
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Speed too slow: {speed:.2f}x (target: 0.55-0.65)")
        elif 0.65 < speed <= 0.8:
            # Partial credit: speed changed but not slow enough
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Speed not slow enough: {speed:.2f}x (target: 0.55-0.65)")
        elif speed == 1.0:
            feedback_parts.append(f"❌ Speed unchanged (still at default 1.0x)")
        else:
            feedback_parts.append(f"❌ Speed incorrect: {speed:.2f}x (expected 0.55-0.65)")
        
        # Criterion 2: Time-stretching filter enabled
        time_stretch_active = False
        
        # Check multiple indicators of time-stretch being enabled
        if time_stretch_enabled:
            time_stretch_active = True
        
        if audio_filter and 'scaletempo' in audio_filter.lower():
            time_stretch_active = True
        
        if time_stretch_active:
            criteria_met += 1
            feedback_parts.append("✅ Time-stretching filter enabled (pitch preserved)")
        else:
            feedback_parts.append("❌ Time-stretching NOT enabled (pitch will be shifted)")
        
        # Criterion 3: Config persisted
        if config_found:
            criteria_met += 1
            feedback_parts.append("✅ Configuration persisted to file")
        else:
            feedback_parts.append("⚠️ Configuration file not found")
        
        # Criterion 4: Not pitch-shifted (redundant with criterion 2, but important)
        # This verifies the agent understood the task requirements
        if time_stretch_active and speed != 1.0:
            criteria_met += 1
            feedback_parts.append("✅ Pitch preservation verified (usable for transcription)")
        elif speed != 1.0 and not time_stretch_active:
            # Speed changed but no time-stretch = pitch-shifted (unusable)
            feedback_parts.append("❌ Audio will be pitch-shifted (UNUSABLE for music learning)")
        elif speed == 1.0 and time_stretch_active:
            # Time-stretch enabled but speed not changed
            criteria_met += 0.5
            feedback_parts.append("⚠️ Filter enabled but speed not changed")
        else:
            feedback_parts.append("❌ Neither speed nor time-stretch configured")
        
        # Criterion 5: Practically usable speed (0.4-0.8 range)
        if 0.4 <= speed <= 0.8:
            criteria_met += 1
            feedback_parts.append("✅ Speed is practical for transcription")
        elif speed < 0.4:
            feedback_parts.append(f"⚠️ Speed too extreme: {speed:.2f}x (impractically slow)")
        elif speed > 0.8:
            feedback_parts.append(f"⚠️ Speed too fast for detailed transcription")
        else:
            feedback_parts.append(f"❌ Speed unusable: {speed:.2f}x")
        
        os.unlink(temp_result.name)
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error parsing result JSON: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading transcription result: {str(e)}"
        }
    
    # Optional: Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_transcription_completed.txt", temp_marker.name)
        # Don't add to criteria, just informational
        logger.info("Task completion marker found")
        os.unlink(temp_marker.name)
    except Exception:
        logger.warning("Completion marker not found")
    
    # Optional: Copy VLC config for debugging
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_transcription_vlcrc.txt", temp_config.name)
        with open(temp_config.name, 'r') as f:
            config_snippet = f.read(500)  # First 500 chars
        logger.info(f"VLC config snippet: {config_snippet[:200]}")
        os.unlink(temp_config.name)
    except Exception:
        logger.warning("Could not copy VLC config for debugging")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    feedback = " | ".join(feedback_parts)
    feedback += f"\n\nCriteria met: {criteria_met:.1f}/{total_criteria} ({score}%)"
    feedback += f"\nResult: {'✅ PASS' if passed else '❌ FAIL'}"
    
    # Add helpful context for failure cases
    if not passed:
        if speed == 1.0:
            feedback += "\nHint: Playback speed was not changed from default"
        if not time_stretch_active:
            feedback += "\nHint: Time-stretching filter was not enabled (audio will sound distorted)"
        if speed != 1.0 and not time_stretch_active:
            feedback += "\nCritical Issue: Speed changed without time-stretch = pitch-shifted audio (unusable)"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }