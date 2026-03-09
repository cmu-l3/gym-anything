#!/usr/bin/env python3
"""Verifier for asvs_contamination_cleanup task.

Checks that the agent identified and removed the 4 injected non-security items
from the ASVS document without removing any legitimate ASVS items.

Scoring (100 points):
- Each correctly removed contaminating item: 20 points (4 x 20 = 80)
- No legitimate items removed: 20 points
  (Deduct 10 points per legitimate item incorrectly removed, min 0)

Pass threshold: 60 points (agent must remove at least 3 of 4 + not over-delete)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ASVS_PATH = "/home/ga/Documents/ReqView/asvs_contamination_project/documents/ASVS.json"

# The 4 injected item IDs (as strings)
INJECTED_IDS = {"900", "901", "902", "903"}


def _count_items(items):
    """Count total items recursively."""
    total = 0
    for item in items:
        total += 1
        if 'children' in item:
            total += _count_items(item['children'])
    return total


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


def _collect_all_ids(items):
    """Collect all item IDs recursively."""
    ids = set()
    for item in items:
        ids.add(str(item.get('id', '')))
        if 'children' in item:
            ids.update(_collect_all_ids(item['children']))
    return ids


def verify_asvs_contamination_cleanup(traj, env_info, task_info):
    """Verify that contaminating items were removed from ASVS."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})

    # Copy ASVS.json from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(ASVS_PATH, tmp.name)
        with open(tmp.name) as f:
            asvs = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ASVS.json: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    details = {}

    current_ids = _collect_all_ids(asvs.get('data', []))

    # Check each injected item: was it removed?
    removed_count = 0
    still_present = []
    for injected_id in INJECTED_IDS:
        if injected_id not in current_ids:
            removed_count += 1
            score += 20
            feedback_parts.append(f"ASVS-{injected_id} correctly removed")
        else:
            still_present.append(injected_id)
            feedback_parts.append(f"ASVS-{injected_id} still present (contaminating item not removed)")

    details['removed_count'] = removed_count
    details['still_present'] = still_present

    # Check that no legitimate items were removed
    # We know legitimate IDs are everything that's NOT in INJECTED_IDS
    # We check the total count: after injection there were N items (baseline),
    # after cleanup there should be N - (number removed from INJECTED_IDS)
    # If current count < expected, agent removed legitimate items too
    current_count = _count_items(asvs.get('data', []))
    details['current_item_count'] = current_count

    # Read baseline count (total items after injection)
    try:
        baseline_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/asvs_contamination_initial_count", baseline_tmp.name)
        with open(baseline_tmp.name) as f:
            baseline_count = int(f.read().strip())
        os.unlink(baseline_tmp.name)
    except Exception:
        baseline_count = None

    if baseline_count is not None:
        expected_count = baseline_count - removed_count
        over_removed = max(0, expected_count - current_count)
        details['baseline_count'] = baseline_count
        details['expected_count'] = expected_count
        details['over_removed'] = over_removed

        if over_removed == 0:
            score += 20
            feedback_parts.append("No legitimate items removed")
        else:
            penalty = min(20, over_removed * 10)
            score += max(0, 20 - penalty)
            feedback_parts.append(
                f"{over_removed} legitimate item(s) incorrectly removed (-{penalty} points)"
            )
    else:
        # Cannot check baseline — give partial credit if injected items were removed
        if removed_count >= 3:
            score += 10
            feedback_parts.append("Baseline unavailable — partial credit for removal accuracy")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
