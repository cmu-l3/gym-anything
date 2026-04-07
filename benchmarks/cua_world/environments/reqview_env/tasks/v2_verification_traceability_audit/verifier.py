#!/usr/bin/env python3
"""Verifier for v2_verification_traceability_audit task.

Checks that the agent:
1. Identified and fixed 5 verification traceability issues in the SRS document
   (3 mismatched links + 2 missing links)
2. Updated the Status of each fixed requirement based on its Priority
   (High -> Blocked, Medium/Low -> Reviewed)
3. Did not modify correctly-linked v2.0 requirements (no false positives)

The verification links are stored on TESTS items (TESTS verifies SRS), so the
verifier checks the TESTS document for correct link targets. It also checks the
SRS document for correct status values.

Scoring (100 points):
- Each correctly fixed link (wrong removed + correct present): 12 points x 5 = 60
- Each correct status update: 4 points x 5 = 20
- No false positives (10 unchanged v2.0 items): 2 points x 10 = 20

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

SRS_PATH = "/home/ga/Documents/ReqView/v2_verification_audit_project/documents/SRS.json"
TESTS_PATH = "/home/ga/Documents/ReqView/v2_verification_audit_project/documents/TESTS.json"


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


def _collect_all_items(items):
    """Collect all items recursively into a flat list."""
    result = []
    for item in items:
        result.append(item)
        if 'children' in item:
            result.extend(_collect_all_items(item['children']))
    return result


def _find_tests_verifying(all_test_items, srs_target):
    """Find all TESTS items that have a verification link to a given SRS item."""
    srs_ref = f"SRS-{srs_target}"
    verifying = []
    for item in all_test_items:
        ver_links = item.get('links', {}).get('verification', [])
        if srs_ref in ver_links:
            verifying.append(str(item.get('id', '?')))
    return verifying


def verify_v2_verification_traceability_audit(traj, env_info, task_info):
    """Verify that verification traceability issues were correctly fixed."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    corrupted_items = metadata.get('corrupted_items', [])
    v2_item_ids = metadata.get('v2_item_ids', [])
    expected_status_map = metadata.get('expected_status', {})

    # Copy documents from VM
    tmp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_tests = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(SRS_PATH, tmp_srs.name)
        with open(tmp_srs.name) as f:
            srs = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read SRS.json: {e}"}
    finally:
        if os.path.exists(tmp_srs.name):
            os.unlink(tmp_srs.name)

    try:
        copy_from_env(TESTS_PATH, tmp_tests.name)
        with open(tmp_tests.name) as f:
            tests = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read TESTS.json: {e}"}
    finally:
        if os.path.exists(tmp_tests.name):
            os.unlink(tmp_tests.name)

    all_test_items = _collect_all_items(tests.get('data', []))

    score = 0
    feedback_parts = []
    details = {}

    # ----------------------------------------------------------------
    # Check each corrupted item for correct fix
    # ----------------------------------------------------------------
    corrupted_srs_ids = set()
    for spec in corrupted_items:
        srs_id = spec['srs_id']
        issue = spec['issue']
        correct_test_id = spec['correct_test_id']
        priority = spec.get('priority', 'M')
        corrupted_srs_ids.add(srs_id)

        item_detail = {'srs_id': srs_id, 'issue': issue}

        # Check that the correct TESTS item now verifies this SRS item
        verifying_test_ids = _find_tests_verifying(all_test_items, srs_id)
        correct_present = correct_test_id in verifying_test_ids
        item_detail['verifying_test_ids'] = verifying_test_ids
        item_detail['correct_present'] = correct_present

        # For mismatches, also check the wrong link was removed
        if issue == 'mismatch':
            wrong_test_id = spec.get('wrong_test_id', '')
            wrong_removed = wrong_test_id not in verifying_test_ids
            item_detail['wrong_removed'] = wrong_removed

            if correct_present and wrong_removed:
                score += 12
                feedback_parts.append(
                    f"SRS-{srs_id}: fixed (wrong TESTS-{wrong_test_id} removed, "
                    f"correct TESTS-{correct_test_id} linked)"
                )
            elif correct_present:
                score += 8
                feedback_parts.append(
                    f"SRS-{srs_id}: partially fixed (correct link added but "
                    f"wrong TESTS-{wrong_test_id} not removed)"
                )
            elif wrong_removed:
                score += 4
                feedback_parts.append(
                    f"SRS-{srs_id}: wrong link removed but correct "
                    f"TESTS-{correct_test_id} not linked"
                )
            else:
                feedback_parts.append(
                    f"SRS-{srs_id}: not fixed (still linked to wrong "
                    f"TESTS-{wrong_test_id})"
                )
        else:
            # Missing link
            if correct_present:
                score += 12
                feedback_parts.append(
                    f"SRS-{srs_id}: fixed (TESTS-{correct_test_id} linked)"
                )
            else:
                feedback_parts.append(
                    f"SRS-{srs_id}: not fixed (still missing verification link)"
                )

        # Check status update
        srs_item = _find_by_id(srs.get('data', []), srs_id)
        if srs_item:
            actual_status = srs_item.get('status', '')
            expected_status = expected_status_map.get(priority, 'Reviewed')
            item_detail['expected_status'] = expected_status
            item_detail['actual_status'] = actual_status
            if actual_status == expected_status:
                score += 4
                feedback_parts.append(f"  Status correctly set to '{expected_status}'")
            else:
                feedback_parts.append(
                    f"  Status wrong: expected '{expected_status}', "
                    f"got '{actual_status}'"
                )

        details[f"SRS-{srs_id}"] = item_detail

    # ----------------------------------------------------------------
    # Check for false positives (unchanged v2.0 items)
    # ----------------------------------------------------------------
    unchanged_count = 0
    false_positives = 0
    for v2_id in v2_item_ids:
        if v2_id in corrupted_srs_ids:
            continue  # Already checked above

        srs_item = _find_by_id(srs.get('data', []), v2_id)
        if not srs_item:
            continue

        actual_status = srs_item.get('status', '')
        if actual_status == 'Approved':
            # Status unchanged from setup — good
            score += 2
            unchanged_count += 1
        else:
            false_positives += 1
            feedback_parts.append(
                f"FALSE POSITIVE: SRS-{v2_id} status changed from "
                f"'Approved' to '{actual_status}'"
            )

    details['unchanged_items'] = unchanged_count
    details['false_positives'] = false_positives
    if unchanged_count > 0:
        feedback_parts.append(
            f"{unchanged_count} correctly-linked v2.0 items left unchanged"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
