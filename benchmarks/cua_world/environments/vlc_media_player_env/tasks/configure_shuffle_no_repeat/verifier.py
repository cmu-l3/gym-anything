#!/usr/bin/env python3
"""
Verifier for Configure Shuffle No Repeat task
"""

import sys
import os
import logging
import tempfile
import json

# Add utils directory to path - use relative path since verifier runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import parse_vlc_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_shuffle_no_repeat(traj, env_info, task_info):
    """
    Verify configure shuffle no repeat task completion.

    Checks:
    1. VLC config file is accessible and parseable
    2. Shuffle/random mode is enabled (random=1)
    3. Repeat-all mode is enabled (loop=1) and repeat-one is NOT enabled (repeat=0 or not set to 1)

    VLC config settings:
    - random=1: Shuffle/random playback enabled
    - loop=1: Repeat all playlist (continuous playback)
    - repeat=1: Repeat one item (NOT desired for this task)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    # Copy VLC config file
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    try:
        try:
            copy_from_env("/tmp/vlc_shuffle_config.txt", temp_config.name)
        except Exception as e:
            logger.error(f"Error copying VLC config: {e}", exc_info=True)
            return {"passed": False, "score": 0, "feedback": f"Cannot access VLC config: {str(e)}"}

        # Parse VLC config
        config = parse_vlc_config(temp_config.name)

        if not config:
            return {"passed": False, "score": 0, "feedback": "VLC config is empty or invalid"}

        criteria_met += 1
        feedback_parts.append("✅ VLC config accessible")

        # Criterion 2: Check shuffle/random mode
        random_mode = config.get('random', '0')
        
        if random_mode == '1':
            criteria_met += 1
            feedback_parts.append("✅ Shuffle mode enabled (random=1)")
        else:
            feedback_parts.append(f"❌ Shuffle mode not enabled (random={random_mode})")

        # Criterion 3: Check repeat modes
        loop_mode = config.get('loop', '0')
        repeat_one = config.get('repeat', '0')

        # For correct configuration:
        # - loop should be 1 (repeat all playlist)
        # - repeat should NOT be 1 (would repeat single item)
        
        if loop_mode == '1' and repeat_one != '1':
            criteria_met += 1
            feedback_parts.append(f"✅ Repeat-all enabled, repeat-one disabled (loop={loop_mode}, repeat={repeat_one})")
        elif loop_mode == '1' and repeat_one == '1':
            feedback_parts.append(f"⚠️ Repeat-all enabled but repeat-one also enabled (will play same video repeatedly)")
        elif loop_mode != '1':
            feedback_parts.append(f"❌ Repeat-all not enabled (loop={loop_mode}, playlist will stop after last video)")
        else:
            feedback_parts.append(f"❌ Incorrect repeat configuration (loop={loop_mode}, repeat={repeat_one})")

        os.unlink(temp_config.name)

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error verifying config: {str(e)}"}

    # Optional: Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_shuffle_completed.txt", temp_marker.name)
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")

    # Optional: Try to get runtime data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_shuffle_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        
        runtime_captured = result.get('runtime_captured', False)
        if runtime_captured:
            shuffle_enabled = result.get('shuffle_enabled', 'unknown')
            feedback_parts.append(f"Runtime check: shuffle={shuffle_enabled}")
        
        os.unlink(temp_result.name)
    except Exception:
        pass  # Runtime data is optional

    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }