#!/usr/bin/env python3
"""Verifier for update_requirement_status task.

Checks that the agent found the requirement about 'minimum password length'
and changed its Status from 'Draft' to 'Ready'.

Verification is done by reading SRS.json directly from the VM.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/update_req_status_project/documents/SRS.json"


def _strip_html(text):
    """Remove HTML tags from text."""
    return re.sub(r'<[^>]+>', '', str(text)).strip()


def _find_matching(items, text_contains):
    """Recursively search for a requirement whose text contains the given string."""
    for item in items:
        item_text = _strip_html(item.get('text', ''))
        if text_contains.lower() in item_text.lower():
            return item
        if 'children' in item:
            result = _find_matching(item['children'], text_contains)
            if result:
                return result
    return None


def verify_update_requirement_status(traj, env_info, task_info):
    """Verify the target requirement's status was updated to the expected value."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    text_contains = metadata.get('target_text_contains', 'minimum password length')
    target_status = metadata.get('target_status', 'Ready')

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

    # Check 1: Target requirement exists in document (40 points)
    match = _find_matching(srs.get('data', []), text_contains)
    if not match:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Requirement with text '{text_contains}' not found in SRS — setup may have failed"
        }

    score += 40
    feedback_parts.append(f"Target requirement found (id={match.get('id')})")

    # Check 2: Status was changed to the target value (60 points)
    actual_status = match.get('status', '')
    if actual_status == target_status:
        score += 60
        feedback_parts.append(f"Status correctly set to '{target_status}'")
    else:
        feedback_parts.append(f"Status='{actual_status}' (expected '{target_status}')")

    passed = score >= 100
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "found_item_id": match.get('id'),
            "actual_status": actual_status,
            "expected_status": target_status,
            "found_text": _strip_html(match.get('text', ''))[:120],
        }
    }
