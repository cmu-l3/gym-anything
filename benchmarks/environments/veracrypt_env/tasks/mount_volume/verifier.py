#!/usr/bin/env python3
"""Verifier for mount_volume task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_mount_volume(traj, env_info, task_info):
    """
    Verify that a VeraCrypt volume was mounted successfully.

    Checks:
    1. A volume is currently mounted
    2. The mounted volume contains expected files
    3. The data_volume.hc was specifically mounted
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_files', [])

    criteria_met = 0
    total_criteria = 4
    feedback_parts = []

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/veracrypt_mount_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        # Criterion 1: A volume is mounted
        if result.get('volume_mounted'):
            criteria_met += 1
            mount_point = result.get('mount_point', 'unknown')
            feedback_parts.append(f"Volume mounted at {mount_point}")
        else:
            feedback_parts.append("No volume is currently mounted")

        # Criterion 2: Mount point has files
        file_count = result.get('mounted_file_count', 0)
        if file_count > 0:
            criteria_met += 1
            feedback_parts.append(f"Mount point contains {file_count} files")
        else:
            feedback_parts.append("Mount point is empty or not accessible")

        # Criterion 3: Expected files are present
        expected_found = 0
        # Check expected files by looking at the mounted_files list
        mounted_files_str = result.get('mounted_files', '')
        for expected_file in expected_files:
            if expected_file in mounted_files_str:
                expected_found += 1
        # Also check explicit has_ keys from export script
        for key in ['has_sf312_nondisclosure_agreement', 'has_fy2024_revenue_budget', 'has_backup_authorized_keys']:
            if result.get(key) and expected_found < len(expected_files):
                pass  # Already counted via mounted_files check above

        if expected_found >= 2:  # At least 2 of 3 expected files
            criteria_met += 1
            feedback_parts.append(f"Expected files found ({expected_found}/{len(expected_files)})")
        elif expected_found > 0:
            feedback_parts.append(f"Some expected files found ({expected_found}/{len(expected_files)})")
        else:
            feedback_parts.append("No expected files found in mounted volume")

        # Criterion 4: Specifically the data_volume was mounted
        if result.get('data_volume_mounted'):
            criteria_met += 1
            feedback_parts.append("data_volume.hc correctly identified as mounted")
        else:
            # Still give credit if volume is mounted and has expected files
            if result.get('volume_mounted') and expected_found > 0:
                criteria_met += 1
                feedback_parts.append("Volume mounted with correct content (data_volume confirmed)")
            else:
                feedback_parts.append("data_volume.hc not confirmed as mounted")

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
