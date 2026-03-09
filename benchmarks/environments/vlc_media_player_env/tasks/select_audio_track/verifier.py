#!/usr/bin/env python3
"""
Verifier for Select Audio Track task

Verifies that the correct audio track (Track 2 / English Dub) was selected
in VLC for a multi-audio-track video file.
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


def verify_select_audio_track(traj, env_info, task_info):
    """
    Verify select audio track task completion.

    Checks:
    1. Audio track result file exists and is valid
    2. Correct audio track is selected (Track 2 / index 1 for English Dub)
    3. VLC was running with the test file

    VLC audio track numbering:
    - UI display: Track 1, Track 2, Track 3 (1-indexed)
    - Internal/RC: 0, 1, 2 (0-indexed)
    - We want Track 2 in UI = index 1 internally
    
    However, different VLC versions may use different indexing in RC interface.
    We accept either:
    - Index 1 (0-indexed, Track 2 in UI)
    - Index 2 (if VLC uses 1-indexed in RC)
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
                "feedback": f"Error copying audio track result: {str(e)}"
            }

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Audio track result accessible")

        # Get audio track info from result
        audio_track_index = result.get('audio_track_index', -1)
        audio_track_info = result.get('audio_track_info', 'Unknown')
        playing_file = result.get('playing_file', '')
        runtime_captured = result.get('runtime_captured', False)
        source = result.get('source', 'unknown')

        logger.info(f"Audio track index: {audio_track_index}")
        logger.info(f"Audio track info: {audio_track_info}")
        logger.info(f"Source: {source}")
        logger.info(f"Runtime captured: {runtime_captured}")

        feedback_parts.append(f"Track: {audio_track_info} [source: {source}]")

        # Criterion 2: Check if correct audio track is selected
        # Accept index 1 (0-indexed: Track 2) or index 2 (1-indexed: Track 2)
        # In most VLC versions with RC interface, tracks are 0-indexed
        # So Track 2 (English Dub) = index 1
        
        if audio_track_index == 1:
            # Perfect - Track 2 (0-indexed = 1)
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append("✅ Correct audio track selected (Track 2 - English Dub, index 1)")
        elif audio_track_index == 2:
            # Also acceptable if VLC uses 1-indexed
            criteria_met += 2
            feedback_parts.append("✅ Correct audio track selected (Track 2 - English Dub, index 2)")
        elif audio_track_index == 0:
            # Still on default track (Japanese)
            feedback_parts.append("❌ Still on default track (Track 1 - Japanese, index 0)")
        elif audio_track_index == -1:
            # Could not determine track
            feedback_parts.append("❌ Audio track not detected")
        else:
            # Some other track
            feedback_parts.append(f"⚠️ Unexpected audio track (index {audio_track_index})")

        # Criterion 3: Verify VLC was running with correct file
        if playing_file and "test_multi_audio" in playing_file:
            criteria_met += 0  # Don't add to criteria, but note it
            feedback_parts.append(f"✓ Playing correct file: {playing_file}")
        else:
            # Still give partial credit if track info was captured
            if runtime_captured or audio_track_index >= 0:
                feedback_parts.append("⚠️ File verification inconclusive")
            else:
                feedback_parts.append("⚠️ VLC may not have played the test file")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid audio track result format: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading audio track result: {str(e)}"
        }

    # Check completion marker (bonus verification)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_track_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    # criteria_met can be 0-3 (1 for result accessible, 2 for correct track, 0 for file check)
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification result: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
