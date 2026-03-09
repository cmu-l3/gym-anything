#!/usr/bin/env python3
"""Verifier for create_encrypted_container task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_encrypted_container(traj, env_info, task_info):
    """
    Verify that a new VeraCrypt encrypted file container was created.

    Checks:
    1. Volume file exists at expected path
    2. Volume size is approximately correct (50MB)
    3. Volume is a valid VeraCrypt container (mountable with expected password)
    4. A new volume was actually created (count increased)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_volume_path', '/home/ga/Volumes/secret_archive.hc')
    expected_size_mb = metadata.get('expected_size_mb', 50)

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/veracrypt_create_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: Volume file exists
        if result.get('volume_exists'):
            criteria_met += 1
            feedback_parts.append(f"Volume file exists at {result.get('volume_path')}")
        else:
            feedback_parts.append(f"Volume file NOT found at {expected_path}")

        # Criterion 2: Volume size is approximately correct
        actual_size_mb = result.get('volume_size_mb', 0)
        size_tolerance = 10  # Allow +/- 10MB tolerance
        if abs(actual_size_mb - expected_size_mb) <= size_tolerance:
            criteria_met += 1
            feedback_parts.append(f"Volume size correct: {actual_size_mb}MB (expected ~{expected_size_mb}MB)")
        elif actual_size_mb > 0:
            feedback_parts.append(f"Volume size mismatch: {actual_size_mb}MB (expected ~{expected_size_mb}MB)")
        else:
            feedback_parts.append("Volume size is 0 or not available")

        # Criterion 3: Volume is valid (mountable with expected password)
        if result.get('volume_valid'):
            criteria_met += 1
            feedback_parts.append("Volume is valid (mounted successfully with expected password)")
        else:
            mount_result = result.get('mount_test_result', 'not_tested')
            feedback_parts.append(f"Volume validation failed: {mount_result}")

        # Criterion 4: New volume was created (count increased)
        initial_count = result.get('initial_volume_count', 0)
        current_count = result.get('current_volume_count', 0)
        if current_count > initial_count:
            criteria_met += 1
            feedback_parts.append(f"New volume created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new volume detected (count unchanged: {current_count})")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
