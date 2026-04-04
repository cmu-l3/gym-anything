#!/usr/bin/env python3
"""Verifier for migrate_junit4_to_junit5 task."""

import json
import logging
import re
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_junit4_to_junit5(traj, env_info, task_info):
    """
    Verify the migration from JUnit 4 to JUnit 5.
    
    Criteria:
    1. Maven Build Success (all tests passed) - 30 pts
    2. Dependencies Updated (pom.xml has junit-jupiter, no junit 4) - 20 pts
    3. Imports Updated (no org.junit.*, yes org.junit.jupiter.*) - 20 pts
    4. Assertions Updated (assertThrows usage) - 15 pts
    5. Annotation Updates (@BeforeEach etc.) - 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    mvn_exit_code = result.get("mvn_exit_code", -1)
    tests_run = int(result.get("tests_run", 0))
    failures = int(result.get("failures", 0))
    errors = int(result.get("errors", 0))
    pom_content = result.get("pom_content", "")
    acct_test = result.get("account_test_content", "")
    trans_test = result.get("transaction_test_content", "")
    
    expected_count = task_info.get("metadata", {}).get("expected_tests_count", 15)

    # 1. Maven Build (30 pts)
    if mvn_exit_code == 0 and tests_run >= expected_count and failures == 0 and errors == 0:
        score += 30
        feedback_parts.append(f"Build success: All {tests_run} tests passed")
    elif tests_run >= expected_count and (failures > 0 or errors > 0):
        # Partial credit if tests run but some fail
        score += 10
        feedback_parts.append(f"Build failed: {failures} failures, {errors} errors")
    else:
        feedback_parts.append("Build failed or no tests run")

    # 2. Dependencies (20 pts)
    has_jupiter = "junit-jupiter" in pom_content
    has_vintage = "junit-vintage" in pom_content
    has_old_junit = re.search(r"<artifactId>junit</artifactId>\s*<version>4", pom_content)
    
    if has_jupiter:
        if not has_old_junit:
            score += 20
            feedback_parts.append("POM: Added Jupiter, removed JUnit 4")
        else:
            score += 10
            feedback_parts.append("POM: Added Jupiter but kept JUnit 4 dependency")
    else:
        feedback_parts.append("POM: JUnit Jupiter dependency missing")

    # 3. Imports (20 pts)
    # Check for forbidden imports
    forbidden_imports = re.findall(r"import org\.junit\.(Test|Before|After|Assert|BeforeClass|AfterClass)", acct_test + trans_test)
    required_imports = re.findall(r"import org\.junit\.jupiter\.api\.(Test|BeforeEach|AfterEach|Assertions|BeforeAll|AfterAll)", acct_test + trans_test)
    
    if required_imports and not forbidden_imports:
        score += 20
        feedback_parts.append("Imports: Fully migrated to Jupiter API")
    elif required_imports:
        score += 10
        feedback_parts.append("Imports: Mixed Jupiter and legacy imports found")
    else:
        feedback_parts.append("Imports: No Jupiter imports found")

    # 4. Assertions & Exceptions (15 pts)
    # Check for assertThrows usage in TransactionServiceTest (replaced @Test(expected=...))
    has_assert_throws = "assertThrows" in trans_test
    # Check for removal of expected= in @Test
    has_test_expected = re.search(r"@Test\s*\(\s*expected", trans_test)
    
    if has_assert_throws and not has_test_expected:
        score += 15
        feedback_parts.append("Refactoring: assertThrows used correctly")
    elif has_assert_throws:
        score += 10
        feedback_parts.append("Refactoring: assertThrows used but legacy @Test(expected) remains")
    else:
        feedback_parts.append("Refactoring: assertThrows not found")

    # 5. Annotations (15 pts)
    # Check for BeforeEach/AfterEach/BeforeAll/AfterAll
    has_new_annotations = re.search(r"@(BeforeEach|AfterEach|BeforeAll|AfterAll)", acct_test + trans_test)
    has_old_annotations = re.search(r"@(Before|After|BeforeClass|AfterClass)(?!\w)", acct_test + trans_test) # negative lookahead to avoid matching BeforeEach as Before
    
    if has_new_annotations and not has_old_annotations:
        score += 15
        feedback_parts.append("Annotations: Migrated to lifecycle annotations")
    elif has_new_annotations:
        score += 5
        feedback_parts.append("Annotations: Mixed annotations found")
    else:
        feedback_parts.append("Annotations: Legacy annotations still present")

    # Check for modified files
    if not result.get("files_modified_during_task", False):
        score = 0
        feedback_parts = ["ANTI-GAMING: No files modified during task"]

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }