#!/usr/bin/env python3
"""Verifier for requirements_status_reconciliation task.

Checks that the agent corrected the status of 5 SRS requirements from
incorrect values back to 'Released'.

Scoring (100 points):
- Each correctly restored status: 20 points (5 x 20 = 100)

Pass threshold: 60 points (at least 3 of 5 statuses corrected)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/status_reconciliation_project/documents/SRS.json"


def _find_by_id(items, target_id):
    """Recursively search for an item by ID."""
    for item in items:
        if str(item.get('id')) == str(target_id):
            return item
        if 'children' in item:
            result = _find_by_id(item['children'], target_id)
            if result:
                return result
    return None


def verify_requirements_status_reconciliation(traj, env_info, task_info):
    """Verify that SRS requirement statuses were corrected to Released."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    corruptions = metadata.get('status_corruptions', [])

    # Copy SRS.json from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(SRS_PATH, tmp.name)
        with open(tmp.name) as f:
            srs = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read SRS.json: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    details = {}

    for corruption in corruptions:
        srs_id = corruption['srs_id']
        wrong_status = corruption['wrong_status']
        correct_status = corruption['correct_status']

        item = _find_by_id(srs.get('data', []), srs_id)
        if not item:
            feedback_parts.append(f"SRS-{srs_id} not found in document")
            continue

        actual_status = item.get('status', '')
        details[f"SRS-{srs_id}"] = {
            'actual_status': actual_status,
            'expected_status': correct_status,
            'wrong_status': wrong_status
        }

        if actual_status == correct_status:
            score += 20
            feedback_parts.append(
                f"SRS-{srs_id}: status correctly set to '{correct_status}'"
            )
        elif actual_status == wrong_status:
            feedback_parts.append(
                f"SRS-{srs_id}: status still '{wrong_status}' (expected '{correct_status}')"
            )
        else:
            feedback_parts.append(
                f"SRS-{srs_id}: status is '{actual_status}' "
                f"(expected '{correct_status}')"
            )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
