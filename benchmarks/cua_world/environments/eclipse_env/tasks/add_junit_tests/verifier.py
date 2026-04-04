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
    """Verify that JUnit tests were added to the Calculator project.

    Criteria:
    1. CalculatorTest.java exists (15 pts)
    2. Test class has proper JUnit 5 annotations (15 pts)
    3. Has tests for add, subtract, multiply, divide methods (40 pts)
    4. Tests run and pass (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/calculator')
    test_class_path = metadata.get('test_class_path', 'src/test/java/com/example/calculator/CalculatorTest.java')
    min_test_methods = metadata.get('min_test_methods', 5)

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
        """Copy a file from the environment and read its contents."""
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

    # --- Criterion 1: Test class exists (15 points) ---
    test_content = copy_and_read(f"{project_dir}/{test_class_path}")
    if test_content:
        score += 15
        feedback_parts.append("CalculatorTest.java exists")

        # --- Criterion 2: Proper JUnit 5 annotations (15 points) ---
        junit5_score = 0
        if 'org.junit.jupiter' in test_content:
            junit5_score += 5
        if '@Test' in test_content:
            junit5_score += 5
        if re.search(r'import\s+.*org\.junit\.jupiter\.api\.(Test|Assertions)', test_content):
            junit5_score += 5

        score += junit5_score
        feedback_parts.append(f"JUnit 5 setup: {junit5_score}/15 pts")

        # --- Criterion 3: Tests for calculator methods (40 points) ---
        methods_tested = 0
        test_score = 0

        # Verify test content has actual assertions (not just empty test methods)
        # This prevents an agent from creating empty @Test void testAdd() {} methods
        has_assertions = bool(re.search(r'assert[A-Z]\w*\s*\(', test_content))
        has_calculator_instance = bool(re.search(r'Calculator\s+\w+\s*=\s*new\s+Calculator', test_content))

        if not has_assertions:
            feedback_parts.append("WARNING: No assertions found in test class")
        if not has_calculator_instance:
            feedback_parts.append("WARNING: No Calculator instance created")

        # Only award points if there are actual method invocations AND assertions present
        # Pattern requires: method call with arguments (not just method name in signature)

        # Check for add test - must have actual .add() call
        if re.search(r'\w+\.add\s*\([^)]+,[^)]+\)', test_content):
            methods_tested += 1
            test_score += 10
        elif re.search(r'void\s+\w*[Aa]dd\w*\s*\(\s*\)', test_content) and has_assertions:
            # Method signature only gets partial credit if there are assertions somewhere
            methods_tested += 1
            test_score += 5

        # Check for subtract test
        if re.search(r'\w+\.subtract\s*\([^)]+,[^)]+\)', test_content):
            methods_tested += 1
            test_score += 10
        elif re.search(r'void\s+\w*[Ss]ubtract\w*\s*\(\s*\)', test_content) and has_assertions:
            methods_tested += 1
            test_score += 5

        # Check for multiply test
        if re.search(r'\w+\.multiply\s*\([^)]+,[^)]+\)', test_content):
            methods_tested += 1
            test_score += 10
        elif re.search(r'void\s+\w*[Mm]ultiply\w*\s*\(\s*\)', test_content) and has_assertions:
            methods_tested += 1
            test_score += 5

        # Check for divide test (including division by zero test)
        if re.search(r'\w+\.divide\s*\([^)]+,[^)]+\)', test_content) or \
           re.search(r'assertThrows\s*\(\s*ArithmeticException\.class', test_content):
            methods_tested += 1
            test_score += 10
        elif re.search(r'void\s+\w*[Dd]ivide\w*\s*\(\s*\)', test_content) and has_assertions:
            methods_tested += 1
            test_score += 5

        score += test_score
        feedback_parts.append(f"Methods tested: {methods_tested}/4 ({test_score}/40 pts)")

        # Count @Test annotations
        test_count = len(re.findall(r'@Test', test_content))
        feedback_parts.append(f"Test methods found: {test_count}")

    else:
        feedback_parts.append("CalculatorTest.java not found")

    # --- Criterion 4: Tests run and pass (30 points) ---
    try:
        # Check for test class file (indicates tests were compiled)
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/test-classes/com/example/calculator/CalculatorTest.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)

        if magic == b'\xca\xfe\xba\xbe':
            score += 15
            feedback_parts.append("Test class compiled")

            # Check for surefire reports (indicates tests were run)
            result_content = copy_and_read(f"{project_dir}/target/surefire-reports/TEST-com.example.calculator.CalculatorTest.xml")
            if result_content:
                # Parse test results from XML
                tests_match = re.search(r'tests="(\d+)"', result_content)
                failures_match = re.search(r'failures="(\d+)"', result_content)

                if tests_match:
                    tests_run = int(tests_match.group(1))
                    failures = int(failures_match.group(1)) if failures_match else 0

                    if tests_run > 0 and failures == 0:
                        score += 15
                        feedback_parts.append(f"All {tests_run} tests passed")
                    elif tests_run > 0:
                        score += 5
                        feedback_parts.append(f"{tests_run - failures}/{tests_run} tests passed")
                    else:
                        feedback_parts.append("Tests did not run")
            else:
                feedback_parts.append("Surefire reports not found - tests may not have run")

    except Exception as e:
        logger.debug(f"Test verification error: {e}")
        feedback_parts.append("Could not verify test execution")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Add JUnit 5 tests to the Calculator project and run them",
            checklist_items=[
                "Eclipse IDE is open and visible",
                "The calculator project is open",
                "A new test class was created",
                "Test methods with @Test annotations are visible",
                "Tests were run (Run As > JUnit Test or similar)",
                "Test results show in JUnit view (green bar or passed tests)",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 5, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Pass criteria: test file exists, has tests, and tests passed
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
