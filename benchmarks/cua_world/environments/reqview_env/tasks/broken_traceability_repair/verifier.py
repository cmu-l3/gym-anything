#!/usr/bin/env python3
"""Verifier for broken_traceability_repair task.

Checks that the agent repaired 4 corrupted satisfaction links in the SRS document
by replacing invalid NEEDS targets with correct ones.

Scoring (100 points):
- Each correctly repaired link: 25 points (4 x 25 = 100)
  A link is "repaired" if:
  (a) the wrong target (NEEDS-999/998/997/996) is no longer present, AND
  (b) the correct target (NEEDS-27/17/24/21) is present

Pass threshold: 75 points (3 of 4 links repaired)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/broken_traceability_project/documents/SRS.json"


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


def verify_broken_traceability_repair(traj, env_info, task_info):
    """Verify that corrupted satisfaction links were repaired."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    corrupted_links = metadata.get('corrupted_links', [])

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

    for link_spec in corrupted_links:
        srs_id = link_spec['srs_id']
        wrong_target = link_spec['wrong_target']
        correct_target = link_spec['correct_target']

        item = _find_by_id(srs.get('data', []), srs_id)
        if not item:
            feedback_parts.append(f"SRS-{srs_id} not found in document")
            continue

        links = item.get('links', {})
        sat_links = links.get('satisfaction', [])

        wrong_removed = wrong_target not in sat_links
        correct_present = correct_target in sat_links

        if wrong_removed and correct_present:
            score += 25
            feedback_parts.append(
                f"SRS-{srs_id}: repaired ({wrong_target} -> {correct_target})"
            )
        elif correct_present and not wrong_removed:
            score += 15
            feedback_parts.append(
                f"SRS-{srs_id}: correct target added but wrong target not removed"
            )
        elif wrong_removed and not correct_present:
            score += 10
            feedback_parts.append(
                f"SRS-{srs_id}: wrong target removed but correct target not added"
            )
        else:
            feedback_parts.append(
                f"SRS-{srs_id}: not repaired (still has {wrong_target}, "
                f"missing {correct_target})"
            )

        details[f"SRS-{srs_id}"] = {
            "wrong_removed": wrong_removed,
            "correct_present": correct_present,
            "current_sat_links": sat_links
        }

    passed = score >= 75
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
