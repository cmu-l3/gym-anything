#!/usr/bin/env python3
"""
Verifier for Add External Audio Track task
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


def verify_add_external_audio_track(traj, env_info, task_info):
    """
    Verify add external audio track task completion.

    Checks:
    1. Audio track result file exists and is valid
    2. Audio delay was set to approximately +3000ms (±500ms tolerance)
    3. Evidence that external audio track was loaded

    VLC stores audio delay in microseconds in vlcrc as 'audio-desync'
    Target: 3000 ms = 3,000,000 microseconds
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 4  # Increased to 4 for better granularity
    feedback_parts = []

    # Copy audio track result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_audio_track_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying audio track result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Audio track result accessible")

        # Get values from result
        audio_delay_ms = result.get('audio_delay_ms', 0)
        audio_delay_us = int(result.get('audio_delay_us', 0))
        external_track_file = result.get('external_track_file', '')
        audio_track_count = int(result.get('audio_track_count', 1))
        external_track_loaded = result.get('external_track_loaded', False)
        config_checked = result.get('config_checked', False)

        logger.info(f"Audio delay: {audio_delay_ms} ms ({audio_delay_us} μs)")
        logger.info(f"External track file: {external_track_file}")
        logger.info(f"Audio track count: {audio_track_count}")
        logger.info(f"External track loaded: {external_track_loaded}")

        # Criterion 2: Check audio delay setting
        # Target: 3000 ms (3,000,000 microseconds)
        # Tolerance: ±500 ms (±500,000 microseconds)
        target_ms = 3000
        tolerance_ms = 500

        # Use microsecond value if available (more accurate)
        if audio_delay_us != 0:
            delay_ms = audio_delay_us / 1000
        else:
            delay_ms = audio_delay_ms

        feedback_parts.append(f"Audio delay: {delay_ms:.0f} ms (target: {target_ms} ms)")

        if abs(delay_ms - target_ms) <= tolerance_ms:
            criteria_met += 2  # Double weight for critical criterion
            feedback_parts.append(f"✅ Audio delay correctly set ({delay_ms:.0f} ms ≈ {target_ms} ms)")
        elif abs(delay_ms - target_ms) <= tolerance_ms * 2:  # Within 2x tolerance
            criteria_met += 1  # Partial credit
            feedback_parts.append(f"⚠️ Audio delay approximately correct ({delay_ms:.0f} ms, target {target_ms} ms)")
        elif delay_ms != 0:
            criteria_met += 0.5  # At least they changed something
            feedback_parts.append(f"⚠️ Audio delay set but incorrect ({delay_ms:.0f} ms, expected {target_ms} ms)")
        else:
            feedback_parts.append(f"❌ Audio delay not set (still at default 0 ms)")

        # Criterion 3: Check for external track loading evidence
        track_evidence_score = 0

        if 'commentary' in external_track_file.lower():
            track_evidence_score += 0.5
            feedback_parts.append("✅ Commentary file reference found")

        if audio_track_count > 1:
            track_evidence_score += 0.5
            feedback_parts.append(f"✅ Multiple audio tracks detected ({audio_track_count} tracks)")

        if external_track_loaded:
            track_evidence_score += 0.5
            feedback_parts.append("✅ External track loading detected")

        if track_evidence_score >= 0.5:
            criteria_met += 1
        else:
            feedback_parts.append("⚠️ No clear evidence of external track loading")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error parsing result JSON: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}

    # Optional: Check VLC config backup for additional evidence
    temp_vlcrc = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_track_vlcrc_backup.txt", temp_vlcrc.name)
        
        with open(temp_vlcrc.name, 'r') as f:
            vlcrc_content = f.read()
        
        # Additional checks in vlcrc
        if 'audio-desync=' in vlcrc_content and 'audio-desync=0' not in vlcrc_content:
            logger.info("Audio desync setting confirmed in vlcrc")
        
        if 'commentary' in vlcrc_content.lower():
            logger.info("Commentary reference found in vlcrc")
        
        os.unlink(temp_vlcrc.name)
    except Exception as e:
        logger.warning(f"Could not verify vlcrc backup: {e}")

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_audio_track_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification complete: criteria_met={criteria_met}/{total_criteria}, score={score}, passed={passed}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
