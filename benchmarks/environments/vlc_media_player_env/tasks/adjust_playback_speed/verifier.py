#!/usr/bin/env python3
"""
Verifier for Adjust Playback Speed task

Verifies that VLC playback speed was successfully adjusted to 1.5x
using multiple verification approaches for robustness.
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


def verify_adjust_playback_speed(traj, env_info, task_info):
    """
    Verify adjust playback speed task completion.

    Verification Strategy:
    1. Speed result file exists and is parseable (accessibility check)
    2. Playback rate is 1.5x within tolerance (±0.05, i.e., 1.45-1.55)
    3. Speed was changed from default 1.0x (modification check)

    Scoring:
    - All 3 criteria met: 100% (perfect)
    - Criteria 1 + 2: 85% (correct speed, missing change verification)
    - Criteria 1 + 3: 50% (file accessible, speed changed but not to target)
    - Only criteria 1: 33% (file exists but speed incorrect)

    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available - cannot verify task"
        }

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Target playback speed
    TARGET_RATE = 1.5
    TOLERANCE = 0.05  # Allow 1.45 to 1.55
    DEFAULT_RATE = 1.0

    # Copy playback speed result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        # Criterion 1: Result file accessible
        try:
            copy_from_env("/tmp/vlc_speed_result.json", temp_result.name)
            logger.info("Successfully copied speed result file")
        except Exception as e:
            logger.error(f"Error copying speed result: {e}", exc_info=True)
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Speed result file not found or inaccessible: {str(e)}"
            }

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Speed result accessible")

        # Extract playback rate from result
        rate = float(result.get('rate', 1.0))
        rate_percent = result.get('rate_percent', 100.0)
        runtime_captured = result.get('runtime_captured', False)
        source = result.get('source', 'unknown')

        logger.info(f"Playback rate: {rate}x ({rate_percent}%) [source: {source}]")
        feedback_parts.append(f"Rate: {rate:.2f}x ({rate_percent:.0f}%) [source: {source}]")

        # Criterion 2: Rate at target (1.5x ± tolerance)
        rate_diff = abs(rate - TARGET_RATE)
        
        if rate_diff <= TOLERANCE:
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append(f"✅ Rate at target (1.5x ± {TOLERANCE})")
            logger.info(f"Rate matches target: {rate:.2f}x (target: {TARGET_RATE}x)")
        else:
            # Check if at least speed was changed from default
            if abs(rate - DEFAULT_RATE) > 0.05:
                criteria_met += 1  # Partial credit for changing speed
                feedback_parts.append(
                    f"⚠️ Rate changed but not at target (got {rate:.2f}x, target {TARGET_RATE}x, diff: {rate_diff:.2f}x)"
                )
                logger.warning(f"Rate not at target: {rate:.2f}x (expected {TARGET_RATE}x)")
            else:
                feedback_parts.append(
                    f"❌ Rate unchanged from default (still {rate:.2f}x, target {TARGET_RATE}x)"
                )
                logger.error(f"Rate not changed from default: {rate:.2f}x")

        # Additional context: warn if rate is at extreme values
        if rate < 0.5 or rate > 3.0:
            feedback_parts.append(f"⚠️ Rate at extreme value ({rate:.2f}x)")
            logger.warning(f"Rate at unusual value: {rate:.2f}x")

        # Cleanup temp file
        os.unlink(temp_result.name)

    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Speed result file corrupted (invalid JSON): {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Error reading speed result: {str(e)}"
        }

    # Check completion marker (bonus verification)
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_speed_completed.txt", temp_marker.name)
        
        with open(temp_marker.name, 'r') as f:
            marker_content = f.read()
        
        if "completed" in marker_content.lower():
            feedback_parts.append("✅ Task completion marker verified")
            logger.info("Task completion marker found")
        
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found (non-critical)")
        logger.warning("Completion marker not found")

    # Calculate final score
    # Total possible: 3 criteria (1 + 2 for main + 0 implicit for change detection)
    # Actual scoring: criteria_met out of total_criteria
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    # Construct feedback message
    feedback = " | ".join(feedback_parts)

    logger.info(f"Verification complete: passed={passed}, score={score}, criteria_met={criteria_met}/{total_criteria}")

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "rate": rate,
            "rate_percent": rate_percent,
            "target_rate": TARGET_RATE,
            "tolerance": TOLERANCE,
            "rate_diff": rate_diff,
            "source": source,
            "runtime_captured": runtime_captured,
            "criteria_met": criteria_met,
            "total_criteria": total_criteria
        }
    }