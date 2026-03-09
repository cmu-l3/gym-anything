#!/usr/bin/env python3
"""Verifier for fix_failing_tests task."""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_failing_tests(traj, env_info, task_info):
    """
    Verify that all 4 test bugs were fixed in BubbleSortTest.java.

    Scoring (100 points):
    - All 4 tests annotated and running (tests_run == 4): 20 pts
    - Zero test failures: 25 pts
    - Zero test errors: 25 pts
    - assertArrayEquals used for array comparison (not assertEquals): 15 pts
    - BubbleSort.java unmodified (checksum match): 15 pts
    - VLM bonus: up to +10 pts

    Pass threshold: >= 70 points AND tests_run >= 4 AND failures == 0
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/fix-failing-tests')
    expected_test_count = metadata.get('expected_test_count', 4)

    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r', errors='replace') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            return None

    # Try to get result JSON
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        logger.debug(f"Could not read task_result.json: {e}")

    score = 0
    feedback_parts = []

    tests_run = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    tests_error = result.get('tests_error', 0)
    test_source = result.get('test_source', '')

    # If no result JSON, try to read source directly
    if not test_source:
        test_source = copy_and_read(
            f"{project_dir}/src/test/java/com/sorts/BubbleSortTest.java"
        ) or ''

    # --- Criterion 1: All 4 tests run (20 pts) ---
    if tests_run >= expected_test_count:
        score += 20
        feedback_parts.append(f"All {tests_run} tests running (including testAlreadySorted @Test added)")
    elif tests_run >= 3:
        score += 10
        feedback_parts.append(f"Only {tests_run}/4 tests running (missing @Test on one method)")
    else:
        feedback_parts.append(f"Only {tests_run} tests running out of expected {expected_test_count}")

    # --- Criterion 2: Zero failures (25 pts) ---
    if tests_failed == 0 and tests_run > 0:
        score += 25
        feedback_parts.append("No test failures")
    elif tests_failed > 0:
        feedback_parts.append(f"{tests_failed} test failure(s) remain")
    else:
        feedback_parts.append("Tests did not run")

    # --- Criterion 3: Zero errors (25 pts) ---
    if tests_error == 0 and tests_run > 0:
        score += 25
        feedback_parts.append("No test errors")
    elif tests_error > 0:
        feedback_parts.append(f"{tests_error} test error(s) remain")

    # --- Criterion 4: assertArrayEquals used (15 pts) ---
    # Check that the test file uses assertArrayEquals (not assertEquals for arrays)
    if test_source:
        has_assert_array_equals = 'assertArrayEquals' in test_source
        # Also check that the empty array test no longer uses assertEquals with array literals
        empty_arr_fixed = not bool(
            re.search(r'assertEquals\s*\(\s*new\s+int\s*\[\s*\]', test_source)
        )
        if has_assert_array_equals and empty_arr_fixed:
            score += 15
            feedback_parts.append("assertArrayEquals used for array comparison (bug 1 fixed)")
        elif has_assert_array_equals:
            score += 10
            feedback_parts.append("assertArrayEquals present but assertEquals(new int[]{}) may remain")
        else:
            feedback_parts.append("assertArrayEquals not found in test source")
    else:
        feedback_parts.append("Could not read test source file")

    # --- Criterion 5: BubbleSort.java unmodified (15 pts) ---
    initial_checksum = result.get('bubblesort_checksum_initial', '')
    current_checksum = result.get('bubblesort_checksum_current', '')
    if initial_checksum and current_checksum:
        if initial_checksum == current_checksum:
            score += 15
            feedback_parts.append("BubbleSort.java unmodified (correct)")
        else:
            feedback_parts.append("WARNING: BubbleSort.java was modified (should not be changed)")
    else:
        # Try direct file read to spot-check
        impl_source = result.get('impl_source', '') or copy_and_read(
            f"{project_dir}/src/main/java/com/sorts/BubbleSort.java"
        ) or ''
        if 'result[j] > result[j + 1]' in impl_source:
            score += 15
            feedback_parts.append("BubbleSort.java appears unmodified")
        else:
            feedback_parts.append("BubbleSort.java checksum unavailable")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Fix 4 bugs in BubbleSortTest.java in IntelliJ IDEA: "
                "(1) replace assertEquals with assertArrayEquals for array comparison, "
                "(2) fix wrong expected value in testSingleElement, "
                "(3) capture return value of sort() in testUnsortedArray, "
                "(4) add @Test to testAlreadySorted. "
                "Run all 4 tests to confirm they pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the fix-failing-tests project loaded",
                "BubbleSortTest.java is open in the editor",
                "The test runner was executed (Run Tests button or gutter icons used)",
                "The test results panel shows test results",
                "All tests are shown as green/passing in the test results",
                "The editor does not show red error markers in BubbleSortTest.java",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 10, 100)
        if vlm_result:
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    all_tests_pass = tests_run >= expected_test_count and tests_failed == 0 and tests_error == 0
    passed = score >= 70 and all_tests_pass

    if not all_tests_pass and score >= 60:
        feedback_parts.append("NOTE: Task not complete — all 4 tests must pass")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "tests_run": tests_run,
            "tests_failed": tests_failed,
            "tests_error": tests_error,
        }
    }
