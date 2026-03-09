#!/usr/bin/env python3
"""
Verifier for Sync External Audio task
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


def verify_sync_external_audio(traj, env_info, task_info):
    """
    Verify sync external audio task completion.

    Checks:
    1. Audio sync result file exists and is valid
    2. Multiple audio tracks are present (original + external)
    3. External audio track is active (track >= 2)

    VLC audio track indexing:
    - Track 0: Disabled
    - Track 1: First embedded audio (original video audio)
    - Track 2+: Additional tracks (external audio files)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy audio sync result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_audio_sync_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying audio sync result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Audio sync result accessible")

        # Get audio track info from result
        track_count = result.get('audio_track_count', 1)
        active_track = result.get('active_audio_track', 1)
        initial_track = result.get('initial_audio_track', 1)
        external_loaded = result.get('external_audio_loaded', False)
        track_changed = result.get('track_changed', False)
        runtime_captured = result.get('runtime_captured', False)
        source = result.get('source', 'unknown')

        feedback_parts.append(f"Source: {source}, Tracks: {track_count}, Active: {active_track}")

        # Criterion 2: Multiple audio tracks present
        if track_count >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Multiple audio tracks ({track_count} tracks)")
        elif track_changed or external_loaded:
            # Partial credit if we detected a change even if count is unclear
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Audio track changed but count unclear ({track_count} detected)")
        else:
            feedback_parts.append(f"❌ Only {track_count} audio track(s) - external audio not loaded")

        # Criterion 3: External audio track is active
        if active_track >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ External audio track active (Track {active_track})")
        elif track_changed and active_track != initial_track:
            # Partial credit for track change
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Track changed to {active_track} (initial: {initial_track})")
        else:
            feedback_parts.append(f"❌ Original audio still active (Track {active_track})")

        # Additional info
        if runtime_captured:
            feedback_parts.append("✓ Runtime capture successful")
        else:
            feedback_parts.append("⚠ Used fallback detection")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Invalid result format: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {str(e)}"}

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_sync_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
            if "Audio tracks: 2" in marker_content or "Active track: 2" in marker_content:
                feedback_parts.append("✅ Completion marker confirms success")
            else:
                feedback_parts.append("✓ Task completed")
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