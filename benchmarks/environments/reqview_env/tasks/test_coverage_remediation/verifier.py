#!/usr/bin/env python3
"""Verifier for test_coverage_remediation task.

Checks that the agent created 3 new test suites in the TESTS document,
each with a verification traceability link to the corresponding SRS requirement.

Scoring (100 points):
- For each of the 3 required test suites (SRS-61, SRS-72, SRS-76):
  - New test item exists with verification link to correct SRS target: 25 points
  - Test item has a non-empty heading: 5 points
  - Test item has status set: 3 points
  Total per suite: 33 points (3 x 33 = 99, rounded to 100)

Pass threshold: 60 points (at least 2 of 3 test suites fully created)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TESTS_PATH = "/home/ga/Documents/ReqView/test_coverage_project/documents/TESTS.json"


def _strip_html(text):
    return re.sub(r'<[^>]+>', '', str(text)).strip()


def _collect_all_items(items):
    """Collect all items recursively into a flat list."""
    result = []
    for item in items:
        result.append(item)
        if 'children' in item:
            result.extend(_collect_all_items(item['children']))
    return result


def verify_test_coverage_remediation(traj, env_info, task_info):
    """Verify that new test suites with verification links were created."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_suites = metadata.get('required_test_suites', [])

    # Copy TESTS.json from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(TESTS_PATH, tmp.name)
        with open(tmp.name) as f:
            tests = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read TESTS.json: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # Read baseline count
    try:
        baseline_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/test_coverage_baseline_count", baseline_tmp.name)
        with open(baseline_tmp.name) as f:
            baseline_count = int(f.read().strip())
        os.unlink(baseline_tmp.name)
    except Exception:
        baseline_count = None

    all_items = _collect_all_items(tests.get('data', []))

    score = 0
    feedback_parts = []
    details = {}

    # Check baseline: new items were added
    current_count = len(all_items)
    if baseline_count is not None:
        new_items = current_count - baseline_count
        details['baseline_count'] = baseline_count
        details['current_count'] = current_count
        details['new_items'] = new_items
        if new_items <= 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No new items added to TESTS (baseline={baseline_count}, current={current_count})"
            }

    # For each required suite, find a test item with a verification link to the target
    for suite_spec in required_suites:
        srs_target = suite_spec['srs_target']
        suite_detail = {'srs_target': srs_target, 'found': False}

        # Search for any item that has a verification link to this SRS target
        matching_item = None
        for item in all_items:
            ver_links = item.get('links', {}).get('verification', [])
            if srs_target in ver_links:
                matching_item = item
                break

        if matching_item:
            suite_detail['found'] = True
            suite_detail['item_id'] = f"TESTS-{matching_item.get('id', '?')}"

            # Check verification link present (25 points)
            score += 25
            feedback_parts.append(
                f"Test for {srs_target}: verification link found "
                f"(TESTS-{matching_item.get('id', '?')})"
            )

            # Check heading non-empty (5 points)
            heading = _strip_html(matching_item.get('heading', ''))
            suite_detail['heading'] = heading
            if heading:
                score += 5
                feedback_parts.append(f"  heading: '{heading}'")
            else:
                feedback_parts.append(f"  heading is empty")

            # Check status set (3 points)
            status = matching_item.get('status', '')
            suite_detail['status'] = status
            if status:
                score += 3
                feedback_parts.append(f"  status: '{status}'")
            else:
                feedback_parts.append(f"  status not set")
        else:
            feedback_parts.append(
                f"Test for {srs_target}: no test item with verification link found"
            )

        details[srs_target] = suite_detail

    # Round score to nearest integer and cap at 100
    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
