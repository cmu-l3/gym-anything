#!/usr/bin/env python3
"""
Verifier for Apply Effects task
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


def verify_apply_effects(traj, env_info, task_info):
    """
    Verify apply effects task completion.

    Checks:
    1. Effects result file exists and is valid
    2. Video effects settings are present
    3. Multiple effects were applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy effects result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/vlc_effects_result.json", temp_result.name)

        # Parse JSON result
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        criteria_met += 1
        feedback_parts.append("✅ Effects result accessible")

        # Get effects from result
        effects = result.get('effects', {})
        effects_count = result.get('effects_count', 0)
        config_found = result.get('config_found', False)

        if isinstance(effects, dict) and effects:
            effect_names = list(effects.keys())
            feedback_parts.append(f"Effects: {', '.join(effect_names)}")

            if effects_count >= 2:
                criteria_met += 2  # Double weight for main criterion
                feedback_parts.append(f"✅ Multiple effects applied ({effects_count} effects)")
            elif effects_count >= 1:
                criteria_met += 1
                feedback_parts.append(f"⚠️ Some effects found ({effects_count} effect)")
            else:
                feedback_parts.append("❌ No video effects found")
        else:
            feedback_parts.append("❌ No video effects found")

        os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading effects result: {str(e)}"}

    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_effects_completed.txt", temp_marker.name)
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
