#!/usr/bin/env python3
"""
Verifier for Switch Audio Track task

Verifies that the agent successfully switched from default English audio track
to Japanese audio track in a multilingual video.
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


def verify_switch_audio_track(traj, env_info, task_info):
    """
    Verify switch audio track task completion.

    Checks:
    1. Video was loaded and playing
    2. Audio track was switched from default (Track 1/English)
    3. Japanese audio track (Track 2) is now active

    VLC audio track numbering can vary:
    - 0-indexed: Track 1 = 0, Track 2 = 1
    - 1-indexed: Track 1 = 1, Track 2 = 2
    - We consider track >= 1 as switched (conservative approach)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy audio track result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_audio_track_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying audio track result: {e}", exc_info=True)
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not retrieve audio track result: {str(e)}"
            }

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Audio track result accessible")

        # Extract result fields
        audio_track = result.get('audio_track', '')
        audio_track_id = result.get('audio_track_id', '')
        track_switched = result.get('track_switched', False)
        runtime_captured = result.get('runtime_captured', False)
        verification_method = result.get('verification_method', 'none')
        final_status = result.get('final_status', 'unknown')

        logger.info(f"Audio track: {audio_track}, ID: {audio_track_id}, Switched: {track_switched}")
        logger.info(f"Method: {verification_method}, Status: {final_status}")

        # Criterion 2: Check if track was switched
        # We need to be flexible with VLC's indexing
        track_value = None
        
        # Try to parse audio_track as integer
        if audio_track and audio_track not in ['', 'unknown']:
            try:
                track_value = int(audio_track)
            except ValueError:
                logger.warning(f"Could not parse audio_track '{audio_track}' as integer")

        # Criterion 2 & 3: Verify track switch
        if track_switched and track_value is not None:
            if track_value >= 1:
                # Track is 1 or higher - definitely switched to Track 2
                criteria_met += 2  # Full credit for both criteria
                feedback_parts.append(f"✅ Audio track switched to Japanese (Track 2)")
                feedback_parts.append(f"Track value: {track_value} [method: {verification_method}]")
            elif track_value == 0:
                # Track is 0 - might be default or might be Track 2 in 0-indexed system
                # This is ambiguous, so we give partial credit only if marked as switched
                criteria_met += 1
                feedback_parts.append(f"⚠️ Audio track value is 0 (ambiguous - may be Track 1 or Track 2 depending on indexing)")
            else:
                feedback_parts.append(f"❌ Audio track value invalid: {track_value}")
        elif track_value is not None:
            # We have a track value but track_switched is False
            if track_value >= 1:
                # Track value indicates switch even if flag is false
                criteria_met += 2
                feedback_parts.append(f"✅ Audio track appears switched (value: {track_value})")
            else:
                feedback_parts.append(f"❌ Audio track still at default (Track 1/English, value: {track_value})")
        elif final_status == "switched" or final_status == "possibly_switched":
            # No clear track value, but status suggests switch
            criteria_met += 1
            feedback_parts.append(f"⚠️ Audio track may have been switched (status: {final_status})")
        else:
            feedback_parts.append(f"❌ No evidence of audio track switch (status: {final_status})")

        # Provide guidance if task failed
        if criteria_met < 2:
            feedback_parts.append("💡 Hint: Use Audio → Audio Track menu to select Track 2")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Invalid audio track result format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Error verifying audio track: {str(e)}"
        }

    # Check completion marker (optional, doesn't affect main score)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_track_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "Switched: true" in marker_content:
            feedback_parts.append("✅ Task marked as completed")
        
        os.unlink(temp_marker.name)
    except Exception:
        logger.debug("Completion marker not found (non-critical)")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    # Add final verdict
    if passed:
        final_feedback = f"✅ SUCCESS: {feedback}"
    else:
        final_feedback = f"❌ FAILED: {feedback}"

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }
