#!/usr/bin/env python3
"""Verifier for refactor_parameterized_test task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_parameterized_test(traj, env_info, task_info):
    """
    Verify the refactoring of DoseCalculatorTest.java.
    
    Criteria:
    1. Test file exists and compiles (10 pts)
    2. Uses @ParameterizedTest annotation (20 pts)
    3. Uses @CsvSource (or similar data source) (20 pts)
    4. Legacy repetitive methods are removed (20 pts)
    5. All 5 test cases pass execution (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    legacy_methods = metadata.get('legacy_methods', [])
    expected_data_values = metadata.get('expected_data_values', [])
    
    score = 0
    feedback_parts = []
    
    # Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)
        
    file_content = result.get('file_content', '')
    build_success = result.get('build_success', False)
    tests_run = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    
    # --- Criterion 1: File Compilation (10 pts) ---
    if build_success:
        score += 10
        feedback_parts.append("Project compiles successfully.")
    else:
        feedback_parts.append("Project compilation failed.")
        # If it doesn't compile, we can still check code structure, but can't verify execution
    
    # --- Criterion 2 & 3: Annotations (40 pts) ---
    # Check for @ParameterizedTest
    if '@ParameterizedTest' in file_content or 'ParameterizedTest.class' in file_content:
        score += 20
        feedback_parts.append("Used @ParameterizedTest.")
    else:
        feedback_parts.append("Missing @ParameterizedTest annotation.")

    # Check for @CsvSource (or acceptable alternatives like MethodSource/ValueSource)
    if any(src in file_content for src in ['@CsvSource', '@ValueSource', '@MethodSource']):
        score += 20
        feedback_parts.append("Used a parameterized source annotation.")
    else:
        feedback_parts.append("Missing data source annotation (e.g. @CsvSource).")

    # --- Criterion 4: Legacy Methods Removed (20 pts) ---
    # We check if the old method names are still present in the file
    found_legacy = [m for m in legacy_methods if m in file_content]
    if not found_legacy:
        score += 20
        feedback_parts.append("Legacy repetitive methods removed.")
    else:
        # Partial credit if they removed some
        removed_count = len(legacy_methods) - len(found_legacy)
        if removed_count > 0:
            partial = int(20 * (removed_count / len(legacy_methods)))
            score += partial
            feedback_parts.append(f"Removed {removed_count}/{len(legacy_methods)} legacy methods.")
        feedback_parts.append(f"Left legacy methods: {', '.join(found_legacy)}.")

    # --- Criterion 5: Tests Passing (30 pts) ---
    # We expect 5 logical test cases to run.
    # JUnit 5 parameterized tests count each invocation as a 'run'.
    # If they just kept the old tests, they might pass, but they would fail Criteria 4.
    if build_success and tests_failed == 0:
        if tests_run >= 5:
            score += 30
            feedback_parts.append(f"All {tests_run} test cases passed.")
        elif tests_run > 0:
            # If they parameterize but somehow collapse it or run fewer cases
            score += 15
            feedback_parts.append(f"Tests passed but only {tests_run} cases ran (expected 5).")
        else:
            feedback_parts.append("No tests were executed.")
    else:
        feedback_parts.append(f"Tests failed (Failures: {tests_failed}).")

    # --- Bonus Check: Data Preservation (Anti-gaming) ---
    # Ensure they didn't just delete everything and write a dummy test
    preserved_count = 0
    for val in expected_data_values:
        if val in file_content:
            preserved_count += 1
    
    if preserved_count < 2 and score > 50:
        feedback_parts.append("WARNING: Original data values missing from test file.")
        # We don't deduct heavily, but worth noting

    # --- VLM Verification (Optional Boost) ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Refactor repetitive tests into a parameterized test in Eclipse",
            checklist_items=[
                "Eclipse IDE is open",
                "DoseCalculatorTest.java is open in editor",
                "Code changes involving @ParameterizedTest are visible",
                "JUnit view shows passing tests (green bar)"
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            # If programmatic checks failed slightly, VLM can bump score
            # But mostly it confirms they used the IDE
            pass
    except Exception:
        pass

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }