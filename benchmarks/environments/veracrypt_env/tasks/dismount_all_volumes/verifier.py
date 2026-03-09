#!/usr/bin/env python3
"""Verifier for dismount_all_volumes task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dismount_all_volumes(traj, env_info, task_info):
    """
    Verify that all VeraCrypt volumes were dismounted.

    Checks:
    1. No volumes are currently mounted (veracrypt --list shows none)
    2. No active mount points remain
    3. Volumes were actually dismounted (count decreased from initial)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    criteria_met = 0
    total_criteria = 3
    feedback_parts = []

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/veracrypt_dismount_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: All volumes dismounted
        if result.get('all_dismounted'):
            criteria_met += 1
            feedback_parts.append("All volumes dismounted")
        else:
            current = result.get('current_mounted_count', 0)
            feedback_parts.append(f"Volumes still mounted: {current}")

        # Criterion 2: No active mount points
        active_mps = result.get('active_mount_points', 0)
        if active_mps == 0:
            criteria_met += 1
            feedback_parts.append("No active mount points remain")
        else:
            feedback_parts.append(f"Active mount points remain: {active_mps}")

        # Criterion 3: Count decreased from initial
        initial = result.get('initial_mounted_count', 0)
        current = result.get('current_mounted_count', 0)
        if result.get('count_decreased') or (initial > 0 and current == 0):
            criteria_met += 1
            feedback_parts.append(f"Mount count decreased: {initial} -> {current}")
        elif initial == 0:
            # Edge case: nothing was mounted initially
            feedback_parts.append("No volumes were mounted initially (setup may have failed)")
        else:
            feedback_parts.append(f"Mount count unchanged: {initial} -> {current}")

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
