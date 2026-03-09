#!/usr/bin/env python3
"""Verifier for debug_logic_error task."""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debug_logic_error(traj, env_info, task_info):
    """
    Verify that the logic bug in BinarySearch.search() was found and fixed.

    Scoring (100 points):
    - All 9 tests pass (tests_run == 9, failures == 0, errors == 0): 40 pts
    - Loop condition changed to 'left <= right': 25 pts
    - BinarySearchTest.java unmodified: 15 pts
    - BinarySearch.class exists (compiles): 10 pts
    - VLM bonus: up to +10 pts

    Pass threshold: >= 70 points AND all 9 tests pass
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/debug-logic-error')
    expected_test_count = metadata.get('expected_test_count', 9)

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

    # Get result JSON
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
    impl_source = result.get('impl_source', '')
    test_source = result.get('test_source', '')
    class_exists = result.get('class_exists', False)

    # Read source files directly if not in result JSON
    if not impl_source:
        impl_source = copy_and_read(
            f"{project_dir}/src/main/java/com/search/BinarySearch.java"
        ) or ''
    if not test_source:
        test_source = copy_and_read(
            f"{project_dir}/src/test/java/com/search/BinarySearchTest.java"
        ) or ''

    # --- Criterion 1: All tests pass (40 pts) ---
    all_pass = tests_run >= expected_test_count and tests_failed == 0 and tests_error == 0
    if all_pass:
        score += 40
        feedback_parts.append(f"All {tests_run} tests pass")
    elif tests_failed > 0:
        partial = max(0, expected_test_count - tests_failed)
        partial_pts = int(40 * partial / expected_test_count)
        score += partial_pts
        feedback_parts.append(f"{tests_run - tests_failed}/{tests_run} tests pass ({tests_failed} failures)")
    elif tests_run == 0:
        feedback_parts.append("No tests ran")
    else:
        feedback_parts.append(f"Tests ran with {tests_error} error(s)")

    # --- Criterion 2: Loop condition fixed (25 pts) ---
    if impl_source:
        # The correct fix: while (left <= right)
        has_correct_condition = bool(re.search(r'while\s*\(\s*left\s*<=\s*right\s*\)', impl_source))
        has_wrong_condition = bool(re.search(r'while\s*\(\s*left\s*<\s*right\s*\)', impl_source))
        if has_correct_condition and not has_wrong_condition:
            score += 25
            feedback_parts.append("Bug fixed: loop condition changed to 'left <= right'")
        elif has_wrong_condition:
            feedback_parts.append("Bug NOT fixed: loop still uses 'left < right'")
        elif has_correct_condition:
            feedback_parts.append("Correct condition present but wrong condition also present")
        else:
            # Agent may have rewritten the method completely
            feedback_parts.append("Loop condition pattern not found (method may have been rewritten)")
            # Give partial credit if tests pass
            if tests_run > 0 and tests_failed == 0:
                score += 15
    else:
        feedback_parts.append("Could not read BinarySearch.java source")

    # --- Criterion 3: Test file unmodified (15 pts) ---
    initial_test_checksum = result.get('test_checksum_initial', '')
    current_test_checksum = result.get('test_checksum_current', '')
    if initial_test_checksum and current_test_checksum:
        if initial_test_checksum == current_test_checksum:
            score += 15
            feedback_parts.append("BinarySearchTest.java unmodified (correct)")
        else:
            feedback_parts.append("WARNING: BinarySearchTest.java was modified (should not be changed)")
    else:
        # Spot-check: test file should contain the original assertions
        if test_source and 'testSearchSingleElementFound' in test_source:
            score += 15
            feedback_parts.append("BinarySearchTest.java appears unmodified")
        else:
            feedback_parts.append("BinarySearchTest.java integrity could not be verified")

    # --- Criterion 4: Class files exist (10 pts) ---
    if class_exists:
        score += 10
        feedback_parts.append("BinarySearch.class compiled successfully")
    else:
        # Try to check directly
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
            tmp.close()
            copy_from_env(
                f"{project_dir}/target/classes/com/search/BinarySearch.class",
                tmp.name
            )
            with open(tmp.name, 'rb') as f:
                magic = f.read(4)
            os.unlink(tmp.name)
            if magic == b'\xca\xfe\xba\xbe':
                score += 10
                feedback_parts.append("BinarySearch.class compiled (magic bytes verified)")
            else:
                feedback_parts.append("Class file found but invalid")
        except Exception:
            feedback_parts.append("Build not completed (no .class file found)")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Debug a logic error in BinarySearch.java using IntelliJ's debugger. "
                "The search() method returns -1 for elements that exist in the array. "
                "Set breakpoints, step through execution, identify that 'while (left < right)' "
                "should be 'while (left <= right)', fix the bug, and verify all 9 tests pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the debug-logic-error project loaded",
                "BinarySearch.java is visible in the editor",
                "The debugger was used (breakpoints, Debug button, or stepping controls visible)",
                "The test runner was executed after the fix",
                "All tests show as green/passing",
                "No error markers visible in BinarySearch.java",
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
