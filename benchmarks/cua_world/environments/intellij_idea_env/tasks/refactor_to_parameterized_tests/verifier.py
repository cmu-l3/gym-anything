#!/usr/bin/env python3
"""Verifier for refactor_to_parameterized_tests task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_refactor_to_parameterized_tests(traj, env_info, task_info):
    """
    Verify that redundant tests were refactored to a parameterized test.

    Criteria:
    1. Tests Pass: Build success & 0 failures (30 pts)
    2. Test Count Maintained: At least 8 tests run (20 pts)
    3. Use of Parameterization: @ParameterizedTest annotation present (25 pts)
    4. Refactoring Complete: Redundant method names removed (15 pts)
    5. Data Source Used: @CsvSource, @MethodSource, etc. present (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    redundant_methods = metadata.get('redundant_methods', [])

    score = 0
    feedback_parts = []

    # Read result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Extract data
    build_success = result.get('build_success', False)
    tests_run = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    test_content = result.get('test_content', "")
    file_modified = result.get('file_modified', False)

    # --- Criterion 1: Tests Pass (30 pts) ---
    if build_success and tests_failed == 0:
        score += 30
        feedback_parts.append("Tests passed successfully")
    elif build_success:
        score += 10
        feedback_parts.append(f"Build success but {tests_failed} tests failed")
    else:
        feedback_parts.append("Build failed")

    # --- Criterion 2: Test Count Maintained (20 pts) ---
    # We expect 8 tests (or more). If they consolidated into one method but
    # it runs 8 times (parameterized), JUnit reports 8 tests run.
    if tests_run >= 8:
        score += 20
        feedback_parts.append(f"Test count maintained ({tests_run} tests run)")
    elif tests_run > 0:
        # Partial credit if some tests ran but count dropped (maybe they deleted some scenarios)
        score += 5
        feedback_parts.append(f"Test count dropped to {tests_run} (expected 8)")
    else:
        feedback_parts.append("No tests ran")

    # --- Criterion 3: Use of Parameterization (25 pts) ---
    has_parameterized = '@ParameterizedTest' in test_content
    # Check for import just in case
    has_import = 'org.junit.jupiter.params.ParameterizedTest' in test_content

    if has_parameterized:
        score += 25
        feedback_parts.append("@ParameterizedTest annotation found")
    elif has_import:
        score += 10
        feedback_parts.append("ParameterizedTest import found but annotation missing in code")
    else:
        feedback_parts.append("No @ParameterizedTest found")

    # --- Criterion 4: Refactoring Complete (15 pts) ---
    # Check if the old method names are gone
    methods_found = []
    for method in redundant_methods:
        if method in test_content:
            methods_found.append(method)

    if len(methods_found) == 0:
        if file_modified:
            score += 15
            feedback_parts.append("All redundant methods removed")
        else:
            feedback_parts.append("File not modified (anti-gaming)")
    elif len(methods_found) < len(redundant_methods):
        score += 5
        feedback_parts.append(f"Some redundant methods remain ({len(methods_found)}/{len(redundant_methods)})")
    else:
        feedback_parts.append("Redundant methods still present (refactoring not done)")

    # --- Criterion 5: Data Source Used (10 pts) ---
    data_sources = ['@CsvSource', '@MethodSource', '@ValueSource', '@EnumSource', '@CsvFileSource']
    has_source = any(ds in test_content for ds in data_sources)
    if has_source:
        score += 10
        feedback_parts.append("Data source annotation found")
    else:
        feedback_parts.append("No standard data source annotation (@CsvSource, etc.) found")

    # --- Final Check ---
    passed = score >= 75 and build_success and tests_failed == 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }