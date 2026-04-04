#!/usr/bin/env python3
"""Verifier for add_requirement task.

Checks that the agent added a new requirement to the SRS document with:
- Text containing 'log all authentication failures'
- Status = 'Draft'
- Priority = 'High'

Verification is done by reading SRS.json directly from the VM.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/add_requirement_project/documents/SRS.json"


def _strip_html(text):
    """Remove HTML tags from text."""
    return re.sub(r'<[^>]+>', '', str(text)).strip()


def _get_item_text(item):
    """Get the text of a requirement item, checking both 'text' (HTML) and 'description' fields."""
    text = _strip_html(item.get('text', '') or '')
    if not text:
        text = _strip_html(item.get('description', '') or '')
    return text


def _find_matching(items, text_contains):
    """Recursively search for a requirement whose text contains the given string."""
    for item in items:
        item_text = _get_item_text(item)
        if text_contains.lower() in item_text.lower():
            return item
        if 'children' in item:
            result = _find_matching(item['children'], text_contains)
            if result:
                return result
    return None


# Priority enum key to label mapping (ReqView stores 'H', 'M', 'L' as keys)
_PRIORITY_KEYS = {
    'High': ['High', 'H', 'h', 'high'],
    'Medium': ['Medium', 'M', 'm', 'medium'],
    'Low': ['Low', 'L', 'l', 'low'],
}


def _priority_matches(actual, expected):
    """Check if priority matches, accepting both key ('H') and label ('High') forms."""
    if actual == expected:
        return True
    expected_alts = _PRIORITY_KEYS.get(expected, [expected])
    return actual in expected_alts


def verify_add_requirement(traj, env_info, task_info):
    """Verify a new requirement was added to the SRS document."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text_contains', 'log all authentication failures')
    required_status = metadata.get('required_status', 'Draft')
    required_priority = metadata.get('required_priority', 'High')

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

    # Check 1: Requirement with matching text exists (50 points)
    match = _find_matching(srs.get('data', []), required_text)
    if not match:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No requirement found with text containing '{required_text}'"
        }

    score += 50
    feedback_parts.append(f"Requirement found (id={match.get('id')})")

    # Check 2: Status is correct (25 points)
    actual_status = match.get('status', '')
    if actual_status == required_status:
        score += 25
        feedback_parts.append(f"Status='{required_status}' correct")
    else:
        feedback_parts.append(f"Status='{actual_status}' (expected '{required_status}')")

    # Check 3: Priority is correct (25 points)
    # Note: ReqView stores priority as enum key ('H') not label ('High')
    actual_priority = match.get('priority', '')
    if _priority_matches(actual_priority, required_priority):
        score += 25
        feedback_parts.append(f"Priority='{actual_priority}' correct (matches '{required_priority}')")
    else:
        feedback_parts.append(f"Priority='{actual_priority}' (expected '{required_priority}' or key equivalent)")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "found_item_id": match.get('id'),
            "found_status": match.get('status'),
            "found_priority": match.get('priority'),
            "found_text": _get_item_text(match)[:120],
        }
    }
