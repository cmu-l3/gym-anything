#!/usr/bin/env python3
"""Verifier for add_unit_test task.

Scoring (100 points total):
- NoteValidatorTest.kt exists with >= 3 @Test methods: 20 pts
- NoteFormatterTest.kt exists with >= 3 @Test methods: 20 pts
- NoteTest.kt exists with >= 3 @Test methods: 20 pts
- Tests compile (valid Kotlin with proper imports): 15 pts
- Tests pass when run (test report XML shows all pass): 25 pts
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text_from_env(copy_from_env, container_path: str) -> str:
    """Copy a text file out of the container and return its contents."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except Exception as exc:
        logger.debug("Could not read %s: %s", container_path, exc)
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _count_test_methods(content: str) -> int:
    """Count @Test annotations in Kotlin test file content."""
    return len(re.findall(r'@Test\b', content))


def _check_test_content_validity(content: str) -> bool:
    """Check if test file content looks like valid Kotlin test code."""
    if not content:
        return False
    has_import = bool(re.search(r'import\s+org\.junit', content))
    has_class = bool(re.search(r'class\s+\w+Test', content))
    has_test_annotation = bool(re.search(r'@Test', content))
    has_assert = bool(re.search(r'assert', content, re.IGNORECASE))
    return has_import and has_class and has_test_annotation and has_assert


def verify_add_unit_test(traj, env_info, task_info):
    """Verify that JUnit unit tests were added to the NotepadApp project."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    project_dir = metadata.get("project_dir", "/home/ga/AndroidStudioProjects/NotepadApp")
    test_dir = metadata.get("test_dir", "app/src/test/java/com/example/notepad")
    min_tests = metadata.get("min_tests_per_file", 3)

    test_base = f"{project_dir}/{test_dir}"

    # Read test files directly via copy_from_env
    validator_content = _read_text_from_env(
        copy_from_env, f"{test_base}/NoteValidatorTest.kt"
    )
    formatter_content = _read_text_from_env(
        copy_from_env, f"{test_base}/NoteFormatterTest.kt"
    )
    note_content = _read_text_from_env(
        copy_from_env, f"{test_base}/NoteTest.kt"
    )

    # Read export JSON as supplementary data (for build/test run results)
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")

    # Fall back to export JSON content if direct reads returned empty
    # Note: strip() is needed because bash `echo ""` outputs "\n" which json.dumps
    # serializes as a non-empty string, causing false positives
    if not validator_content:
        validator_content = result.get("validator_test_content", "").strip()
    if not formatter_content:
        formatter_content = result.get("formatter_test_content", "").strip()
    if not note_content:
        note_content = result.get("note_test_content", "").strip()

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Criterion 1: NoteValidatorTest.kt exists with >= 3 @Test (20 pts)
    # ================================================================
    validator_count = _count_test_methods(validator_content)
    details["validator_test_exists"] = bool(validator_content)
    details["validator_test_count"] = validator_count

    if validator_content and validator_count >= min_tests:
        score += 20
        feedback_parts.append(
            f"NoteValidatorTest.kt: {validator_count} test methods (20/20)"
        )
    elif validator_content and validator_count > 0:
        score += 8
        feedback_parts.append(
            f"NoteValidatorTest.kt: only {validator_count} tests, need >= {min_tests} (8/20)"
        )
    elif validator_content:
        score += 4
        feedback_parts.append("NoteValidatorTest.kt: exists but no @Test methods found (4/20)")
    else:
        feedback_parts.append("NoteValidatorTest.kt not found (0/20)")

    # ================================================================
    # Criterion 2: NoteFormatterTest.kt exists with >= 3 @Test (20 pts)
    # ================================================================
    formatter_count = _count_test_methods(formatter_content)
    details["formatter_test_exists"] = bool(formatter_content)
    details["formatter_test_count"] = formatter_count

    if formatter_content and formatter_count >= min_tests:
        score += 20
        feedback_parts.append(
            f"NoteFormatterTest.kt: {formatter_count} test methods (20/20)"
        )
    elif formatter_content and formatter_count > 0:
        score += 8
        feedback_parts.append(
            f"NoteFormatterTest.kt: only {formatter_count} tests, need >= {min_tests} (8/20)"
        )
    elif formatter_content:
        score += 4
        feedback_parts.append("NoteFormatterTest.kt: exists but no @Test methods found (4/20)")
    else:
        feedback_parts.append("NoteFormatterTest.kt not found (0/20)")

    # ================================================================
    # Criterion 3: NoteTest.kt exists with >= 3 @Test (20 pts)
    # ================================================================
    note_count = _count_test_methods(note_content)
    details["note_test_exists"] = bool(note_content)
    details["note_test_count"] = note_count

    if note_content and note_count >= min_tests:
        score += 20
        feedback_parts.append(
            f"NoteTest.kt: {note_count} test methods (20/20)"
        )
    elif note_content and note_count > 0:
        score += 8
        feedback_parts.append(
            f"NoteTest.kt: only {note_count} tests, need >= {min_tests} (8/20)"
        )
    elif note_content:
        score += 4
        feedback_parts.append("NoteTest.kt: exists but no @Test methods found (4/20)")
    else:
        feedback_parts.append("NoteTest.kt not found (0/20)")

    # ================================================================
    # Criterion 4: Tests compile (15 pts)
    # ================================================================
    # Check export JSON flag first
    compiles = result.get("tests_compile", False)

    # Also check by reading gradle output directly
    if not compiles:
        gradle_log = _read_text_from_env(copy_from_env, "/tmp/gradle_test_output.log")
        if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
            compiles = True

    details["tests_compile"] = compiles

    if compiles:
        score += 15
        feedback_parts.append("Tests compile successfully (15/15)")
    else:
        # Fallback: check if test file contents look like valid Kotlin
        valid_count = sum(1 for c in [validator_content, formatter_content, note_content]
                         if _check_test_content_validity(c))
        if valid_count >= 2:
            score += 7
            feedback_parts.append(
                f"Test content looks valid ({valid_count}/3 files) but compilation not confirmed (7/15)"
            )
        else:
            feedback_parts.append("Tests do not compile or content is invalid (0/15)")

    # ================================================================
    # Criterion 5: Tests pass when run (25 pts)
    # ================================================================
    # Check export JSON for test results
    tests_ran = result.get("tests_ran", False)
    total_tests = result.get("total_tests", 0)
    passed_tests = result.get("passed_tests", 0)
    failed_tests = result.get("failed_tests", 0)

    details["tests_ran"] = tests_ran
    details["total_tests"] = total_tests
    details["passed_tests"] = passed_tests
    details["failed_tests"] = failed_tests

    if tests_ran and total_tests > 0 and failed_tests == 0:
        score += 25
        feedback_parts.append(f"All {passed_tests} tests passed (25/25)")
    elif tests_ran and total_tests > 0 and passed_tests > 0:
        pass_ratio = passed_tests / total_tests
        partial = int(25 * pass_ratio)
        score += partial
        feedback_parts.append(
            f"{passed_tests}/{total_tests} tests passed, {failed_tests} failed ({partial}/25)"
        )
    elif tests_ran and total_tests == 0:
        feedback_parts.append("Gradle ran but no test results found (0/25)")
    else:
        feedback_parts.append("Tests did not run successfully (0/25)")

    # ================================================================
    # Final result
    # ================================================================
    passed = score >= 70

    details["total_score"] = score

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
