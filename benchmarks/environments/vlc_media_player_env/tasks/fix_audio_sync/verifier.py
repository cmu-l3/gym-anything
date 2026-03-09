#!/usr/bin/env python3
"""
Verifier for Fix Audio Sync task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_audio_sync(traj, env_info, task_info):
    """
    Verify fix audio sync task completion.

    Checks:
    1. Audio sync result file exists and is valid
    2. Audio delay setting is present (non-zero)
    3. Audio delay is POSITIVE (delaying audio to match video)
    4. Audio delay is in reasonable range (100-800ms for ~350ms correction)

    Audio sync problem: Audio arrives ~350ms too early
    Solution: Apply +300 to +400ms delay (positive value)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    # Copy audio sync result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dir = None

    try:
        # Copy result file
        try:
            copy_from_env("/tmp/vlc_audio_sync_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying audio sync result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Audio sync result not found: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Audio sync result accessible")

        # Get audio delay from result
        audio_delay = result.get('audio_delay_ms', 0)
        config_found = result.get('config_found', False)
        source = result.get('source', 'unknown')

        logger.info(f"Audio delay: {audio_delay}ms, source: {source}, config_found: {config_found}")

        # Criterion 2: Audio delay setting is present and non-zero
        if audio_delay != 0:
            criteria_met += 1
            feedback_parts.append(f"✅ Audio delay configured: {audio_delay}ms")
        else:
            feedback_parts.append("❌ No audio delay adjustment found (still at 0ms)")
            # Early return with partial score
            score = int((criteria_met / total_criteria) * 100)
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | Hint: Use Tools → Track Synchronization or press 'j' key to delay audio"
            }

        # Criterion 3: Audio delay is POSITIVE (delaying audio to match video)
        if audio_delay > 0:
            criteria_met += 1
            feedback_parts.append(f"✅ Delay direction correct (positive = audio delayed)")
        else:
            feedback_parts.append(f"❌ Delay direction wrong ({audio_delay}ms is negative, should be positive)")
            feedback_parts.append("Hint: Audio arrives TOO EARLY, so you need to DELAY it (positive value)")
            # Continue to check range anyway

        # Criterion 4: Audio delay is in reasonable range (100-800ms)
        # The sync issue is ~350ms, so reasonable correction is 100-800ms
        if 100 <= audio_delay <= 800:
            criteria_met += 1
            feedback_parts.append(f"✅ Delay value reasonable for ~350ms sync issue")
        elif audio_delay > 0:
            if audio_delay < 100:
                feedback_parts.append(f"⚠️ Delay too small ({audio_delay}ms). The sync issue is ~350ms, try 300-400ms")
            else:  # > 800
                feedback_parts.append(f"⚠️ Delay too large ({audio_delay}ms). The sync issue is ~350ms, try 300-400ms")
        else:
            feedback_parts.append(f"❌ Negative delay makes the problem worse")

        # Also copy config file for debugging if available
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/vlc_audio_sync_config.txt", temp_config.name)
            
            with open(temp_config.name, 'r') as f:
                config_content = f.read()
            
            # Look for audio delay settings in config
            if 'audio-desync=' in config_content or 'desync=' in config_content or 'audio-delay=' in config_content:
                logger.info("Audio delay setting found in vlcrc config")
            else:
                logger.warning("No audio delay setting found in vlcrc - may not persist")
                feedback_parts.append("⚠️ Setting may not be saved to config")
            
            os.unlink(temp_config.name)
        except Exception as e:
            logger.info(f"Could not verify config file: {e}")

        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON parse error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Invalid result format: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    # Add helpful hint if failed
    if not passed and audio_delay == 0:
        feedback += " | 💡 Tip: Open Tools → Track Synchronization, set Audio desync to ~350ms"
    elif not passed and audio_delay < 0:
        feedback += " | 💡 Tip: Positive values delay audio, negative values advance it. You need positive here."

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }