#!/usr/bin/env python3
"""Verifier for create_keyfile task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_keyfile(traj, env_info, task_info):
    """
    Verify that a VeraCrypt keyfile was generated.

    Checks:
    1. Keyfile exists at expected path
    2. Keyfile is valid (at least 64 bytes, as VeraCrypt keyfiles are typically 64 bytes)
    3. A new keyfile was created (file count increased)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_keyfile_path', '/home/ga/Keyfiles/my_keyfile.key')

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/veracrypt_keyfile_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Keyfile exists at expected path
        if result.get('keyfile_exists'):
            criteria_met += 1
            feedback_parts.append(f"Keyfile exists at {result.get('keyfile_path')}")
        else:
            # Check if a keyfile was created elsewhere
            other = result.get('other_keyfiles', '')
            if other:
                feedback_parts.append(f"Keyfile NOT at expected path, but found: {other}")
            else:
                feedback_parts.append(f"Keyfile NOT found at {expected_path}")

        # Criterion 2: Keyfile is valid size
        if result.get('keyfile_valid'):
            criteria_met += 1
            size = result.get('keyfile_size', 0)
            feedback_parts.append(f"Keyfile is valid ({size} bytes)")
        else:
            size = result.get('keyfile_size', 0)
            if size > 0:
                feedback_parts.append(f"Keyfile too small ({size} bytes, need >= 64)")
            else:
                feedback_parts.append("Keyfile not found or empty")

        # Criterion 3: New keyfile was created
        if result.get('new_keyfile_created'):
            criteria_met += 1
            initial = result.get('initial_keyfile_count', 0)
            current = result.get('current_keyfile_count', 0)
            feedback_parts.append(f"New keyfile created (count: {initial} -> {current})")
        else:
            feedback_parts.append("No new keyfile detected in Keyfiles directory")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 66  # Need at least 2 of 3

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
