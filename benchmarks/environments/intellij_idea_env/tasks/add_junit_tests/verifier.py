#!/usr/bin/env python3
"""Verifier for add_junit_tests task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_junit_tests(traj, env_info, task_info):
    """Verify that JUnit tests were added correctly.

    Criteria:
    1. JUnit dependency added to pom.xml (20 pts)
    2. Test file created with @Test annotations (20 pts)
    3. At least 3 test methods (15 pts)
    4. Tests cover add, subtract, multiply methods (15 pts)
    5. All tests pass (Maven surefire reports) (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/calculator-test')

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # --- Criterion 1: JUnit dependency in pom.xml (20 pts) ---
    pom_content = copy_and_read(f"{project_dir}/pom.xml")
    if pom_content:
        has_junit = bool(re.search(r'<artifactId>\s*junit\s*</artifactId>', pom_content))
        has_junit_jupiter = bool(re.search(r'<artifactId>\s*junit-jupiter', pom_content))
        has_test_scope = bool(re.search(r'<scope>\s*test\s*</scope>', pom_content))

        if (has_junit or has_junit_jupiter) and has_test_scope:
            score += 20
            dep_name = "JUnit" if has_junit else "JUnit Jupiter"
            feedback_parts.append(f"{dep_name} dependency added with test scope")
        elif has_junit or has_junit_jupiter:
            score += 15
            feedback_parts.append("JUnit dependency added (missing test scope)")
        else:
            feedback_parts.append("JUnit dependency not found in pom.xml")
    else:
        feedback_parts.append("pom.xml not found")

    # --- Criterion 2: Test file exists with @Test (20 pts) ---
    test_content = None
    expected_test = metadata.get('expected_test_file',
                                  'src/test/java/com/kranonit/calculator/CalculatorTest.java')

    # Try expected path first
    test_content = copy_and_read(f"{project_dir}/{expected_test}")

    # Try alternate paths if expected not found
    if not test_content:
        alternates = [
            'src/test/java/com/kranonit/calculator/CalculatorTests.java',
            'src/test/java/CalculatorTest.java',
        ]
        for alt in alternates:
            test_content = copy_and_read(f"{project_dir}/{alt}")
            if test_content:
                break

    if test_content:
        has_test_annotation = '@Test' in test_content
        has_import = bool(re.search(r'import\s+(org\.junit|static\s+org\.junit)', test_content))

        if has_test_annotation and has_import:
            score += 20
            feedback_parts.append("Test file created with @Test annotations and JUnit imports")
        elif has_test_annotation:
            score += 15
            feedback_parts.append("Test file has @Test annotations (missing JUnit import)")
        else:
            score += 5
            feedback_parts.append("Test file exists but no @Test annotations found")
    else:
        feedback_parts.append("Test file not found")

    # --- Criterion 3: At least 3 test methods (15 pts) ---
    if test_content:
        test_methods = re.findall(r'@Test\s+(?:public\s+)?void\s+(\w+)', test_content)
        num_tests = len(test_methods)

        min_tests = metadata.get('minimum_test_count', 3)
        if num_tests >= min_tests:
            score += 15
            feedback_parts.append(f"{num_tests} test methods found (required: {min_tests})")
        elif num_tests > 0:
            partial = int(15 * (num_tests / min_tests))
            score += partial
            feedback_parts.append(f"Only {num_tests}/{min_tests} test methods found ({partial}/15 pts)")
        else:
            feedback_parts.append("No test methods found")

    # --- Criterion 4: Tests cover required methods (15 pts) ---
    if test_content:
        required = metadata.get('required_tested_methods', ['add', 'subtract', 'multiply'])
        covered = []
        for method in required:
            # Look for calls to calculator.method() or .method(
            if re.search(rf'\.{method}\s*\(', test_content):
                covered.append(method)

        coverage_score = int(15 * (len(covered) / max(len(required), 1)))
        score += coverage_score
        if covered:
            feedback_parts.append(f"Methods tested: {', '.join(covered)} ({coverage_score}/15 pts)")
        else:
            feedback_parts.append("No required methods appear to be tested")

    # --- Criterion 5: All tests pass (30 pts) ---
    # Try reading surefire reports
    tests_passed_count = 0
    tests_run_count = 0
    try:
        # Look for surefire XML reports
        result_json_content = copy_and_read("/tmp/task_result.json")
        if result_json_content:
            result = json.loads(result_json_content)
            test_result = result.get('test_result', 'unknown')
            tests_run_count = result.get('tests_run', 0)
            tests_passed_count = result.get('tests_passed', 0)
            tests_failed = result.get('tests_failed', 0)

            if test_result == 'pass' and tests_run_count > 0 and tests_failed == 0:
                score += 30
                feedback_parts.append(f"All {tests_run_count} tests passed")
            elif tests_run_count > 0:
                partial = int(30 * (tests_passed_count / tests_run_count))
                score += partial
                feedback_parts.append(f"{tests_passed_count}/{tests_run_count} tests passed ({partial}/30 pts)")
            else:
                feedback_parts.append("No tests were run")
        else:
            feedback_parts.append("Could not read test results")
    except Exception as e:
        feedback_parts.append(f"Error reading test results: {e}")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task

        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description="Add JUnit test dependency and write unit tests for Calculator.java "
                           "in IntelliJ IDEA. Add JUnit to pom.xml, create CalculatorTest.java "
                           "with at least 3 test methods covering add, subtract, and multiply.",
            checklist_items=[
                "IntelliJ IDEA is open with the calculator-test project loaded",
                "pom.xml is edited to include JUnit dependency",
                "A test file (CalculatorTest.java) is created or open in the editor",
                "Test methods with @Test annotations are visible in the editor",
                "Tests were executed (Run panel or test results visible)",
                "Test execution results are visible showing passed tests",
            ]
        )
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                score = min(score + 10, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Tests must actually pass - this is the core requirement
    tests_actually_passed = 'All' in ' '.join(feedback_parts) and 'tests passed' in ' '.join(feedback_parts).lower()

    # Must have tests passing to consider the task complete
    passed = score >= 70 and tests_actually_passed

    if not tests_actually_passed and score >= 50:
        feedback_parts.append("NOTE: Task incomplete - tests must pass")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
