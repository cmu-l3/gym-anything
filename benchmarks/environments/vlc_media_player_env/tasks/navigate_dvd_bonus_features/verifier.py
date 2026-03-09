#!/usr/bin/env python3
"""
Verifier for Navigate DVD Bonus Features task
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


def verify_dvd_bonus_navigation(traj, env_info, task_info):
    """
    Verify DVD bonus features navigation task completion.

    Checks:
    1. VLC was running and ISO was loaded
    2. DVD/disc navigation mode was active
    3. Correct title (Title 2) was playing
    4. Playback progressed beyond 10 seconds
    5. No critical errors occurred

    Scoring:
    - VLC + ISO loaded: 20%
    - DVD mode active: 20%
    - Correct title (2): 30%
    - Playback progress: 20%
    - No errors: 10%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_points = 100
    score = 0
    feedback_parts = []

    # Copy DVD navigation result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_dvd_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying DVD result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"DVD result not found: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        logger.info(f"DVD result: {result}")

        # Extract data
        iso_loaded = result.get('iso_loaded', False)
        dvd_mode = result.get('dvd_mode', False)
        title_number = result.get('title_number', '')
        playback_time = result.get('playback_time', 0)
        runtime_captured = result.get('runtime_captured', False)

        # Criterion 1: VLC running with ISO loaded (20 points)
        if iso_loaded or (dvd_mode and title_number):
            score += 20
            criteria_met += 1
            feedback_parts.append("✅ VLC + ISO loaded")
        else:
            feedback_parts.append("❌ ISO not loaded or VLC not running")

        # Criterion 2: DVD mode active (20 points)
        if dvd_mode:
            score += 20
            criteria_met += 1
            feedback_parts.append("✅ DVD navigation mode active")
        else:
            feedback_parts.append("❌ DVD mode not detected (may be simple file playback)")

        # Criterion 3: Correct title playing - Title 2 (30 points)
        # This is the most important criterion
        if title_number == "2":
            score += 30
            criteria_met += 1
            feedback_parts.append("✅ Title 2 (Bonus Features) playing - CORRECT!")
        elif title_number == "1":
            feedback_parts.append("❌ Title 1 (Main Feature) playing - WRONG! Need Title 2")
        elif title_number:
            # Some other title
            score += 10  # Partial credit for navigating to a title
            feedback_parts.append(f"⚠️ Title {title_number} playing (expected Title 2)")
        else:
            # Could not determine title
            # Give partial credit if DVD mode was detected
            if dvd_mode:
                score += 15  # Partial credit
                criteria_met += 0.5
                feedback_parts.append("⚠️ Title number unknown, but DVD mode active (partial credit)")
            else:
                feedback_parts.append("❌ Could not determine title number")

        # Criterion 4: Playback progress >10 seconds (20 points)
        if playback_time >= 10:
            score += 20
            criteria_met += 1
            feedback_parts.append(f"✅ Playback progress: {playback_time}s")
        elif playback_time > 0:
            # Some playback, partial credit
            partial = int(20 * (playback_time / 10))
            score += partial
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Limited playback: {playback_time}s (need 10s+)")
        else:
            feedback_parts.append("❌ No playback progress detected")

        # Criterion 5: No critical errors (10 points)
        # Check VLC log for errors
        temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
        has_errors = False
        
        try:
            copy_from_env("/tmp/vlc_dvd_export.log", temp_log.name)
            
            with open(temp_log.name, 'r') as f:
                log_content = f.read().lower()
            
            # Check for critical errors
            error_keywords = [
                'critical error', 'fatal', 'cannot open', 
                'failed to open', 'no such file'
            ]
            
            for keyword in error_keywords:
                if keyword in log_content:
                    has_errors = True
                    break
            
            os.unlink(temp_log.name)
        except Exception as e:
            logger.warning(f"Could not check VLC log: {e}")
            # Don't penalize if log not available
            pass

        if not has_errors:
            score += 10
            criteria_met += 1
            feedback_parts.append("✅ No critical errors")
        else:
            feedback_parts.append("⚠️ Errors detected in VLC log")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_dvd_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Final assessment
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    feedback = f"Score: {score}/100 | " + feedback

    logger.info(f"Final verification: passed={passed}, score={score}")
    logger.info(f"Feedback: {feedback}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }