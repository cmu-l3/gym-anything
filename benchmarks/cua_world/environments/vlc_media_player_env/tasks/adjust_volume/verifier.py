#!/usr/bin/env python3
"""
Verifier for Adjust Volume task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adjust_volume(traj, env_info, task_info):
    """
    Verify adjust volume task completion.

    Checks:
    1. Volume result file exists and is valid
    2. Volume setting is close to target (75% = 192)
    3. Volume was changed from initial value (256)

    VLC volume range: 0-512, where 256 = 100%
    Target: 75% = 192
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy volume result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        try:
            copy_from_env("/tmp/vlc_volume_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying volume result: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Error copying volume result: {str(e)}"}

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Volume result accessible")

        # Get volume from result
        volume = result.get('volume', 256)
        runtime_captured = result.get('runtime_captured', False)
        source = result.get('source', 'unknown')

        # Calculate percentage
        volume_percent = (volume / 256) * 100

        feedback_parts.append(f"Volume: {volume} ({volume_percent:.0f}%) [source: {source}]")

        # Criterion 2: Volume close to target (75% = 192)
        # Allow tolerance of ±10% (172-212 range)
        target = 192
        tolerance = 20

        if abs(volume - target) <= tolerance:
            criteria_met += 2  # Double weight for main criterion
            feedback_parts.append(f"✅ Volume at target (192 ± {tolerance})")
        elif volume < 256:  # At least it was changed
            criteria_met += 1
            feedback_parts.append(f"⚠️ Volume changed but not at target (got {volume}, target {target})")
        else:
            feedback_parts.append(f"❌ Volume unchanged (still at default 256)")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading volume result: {str(e)}"}

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
