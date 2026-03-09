#!/usr/bin/env python3
"""
Verifier for add_comprehensive_unit_tests task.

Task: Write comprehensive JUnit unit tests for FinancialCalcApp.

Classes to test:
- LoanCalculator (monthly payment, total interest, eligibility)
- InvestmentAnalyzer (ROI, CAGR, Sharpe ratio, volatility)
- BudgetPlanner (savings rate, emergency fund, months to goal)

Scoring (100 points total):
- Test files created (at least 1): 15 pts
- At least 15 @Test methods total: 20 pts
- At least 2 of 3 classes covered: 15 pts
- Edge case / exception tests present: 20 pts
- All tests pass (./gradlew test): 30 pts

Pass threshold: 70/100
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _read_text(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except Exception:
        return ""
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _read_json(copy_from_env, path):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def verify_add_comprehensive_unit_tests(traj, env_info, task_info):
    """Verify comprehensive unit tests for FinancialCalcApp."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/AndroidStudioProjects/FinancialCalcApp')
    pkg_path = metadata.get('package_path', 'com/example/financialcalc')
    test_dir = f"{project_dir}/app/src/test/java/{pkg_path}"

    result = _read_json(copy_from_env, "/tmp/task_result.json")

    # Read test file contents from result JSON (export collects them)
    test_contents = result.get('test_contents', '')
    test_file_count = result.get('test_file_count', 0)
    test_annotation_count = result.get('test_annotation_count', 0)
    test_success = result.get('test_success', False)
    test_passed = result.get('test_passed', 0)
    test_failed = result.get('test_failed', 0)

    # Also try to read test files directly
    if not test_contents:
        for candidate in [
            f"{test_dir}/LoanCalculatorTest.kt",
            f"{test_dir}/InvestmentAnalyzerTest.kt",
            f"{test_dir}/BudgetPlannerTest.kt",
            f"{test_dir}/FinancialTests.kt",
            f"{test_dir}/CalculatorTests.kt",
        ]:
            content = _read_text(copy_from_env, candidate)
            if content:
                test_contents += f"\n{content}"
                test_file_count += 1

    # Recount @Test annotations from direct reads
    if test_contents and test_annotation_count == 0:
        test_annotation_count = len(re.findall(r'@Test\b', test_contents))

    score = 0
    feedback = []

    # GATE: Must have at least one test file
    if test_file_count == 0 and not test_contents:
        return {"passed": False, "score": 0, "feedback": "No test files found — nothing to score"}

    # ================================================================
    # Criterion 1: Test files created (15 pts)
    # ================================================================
    try:
        if test_file_count >= 3:
            score += 15
            feedback.append(f"Criterion1 Test files: {test_file_count} files (15/15)")
        elif test_file_count == 2:
            score += 12
            feedback.append(f"Criterion1 Test files: {test_file_count} files (12/15)")
        elif test_file_count == 1:
            score += 8
            feedback.append(f"Criterion1 Test files: {test_file_count} file (8/15)")
        elif test_contents:
            score += 5
            feedback.append("Criterion1 Test files: found content but no counted files (5/15)")
        else:
            feedback.append("Criterion1 Test files: none found (0/15)")
    except Exception as e:
        feedback.append(f"Criterion1: error ({e}) (0/15)")

    # ================================================================
    # Criterion 2: At least 15 @Test methods (20 pts)
    # ================================================================
    try:
        count = test_annotation_count if test_annotation_count > 0 else len(re.findall(r'@Test\b', test_contents))

        if count >= 20:
            score += 20
            feedback.append(f"Criterion2 @Test count: {count} (20/20)")
        elif count >= 15:
            score += 20
            feedback.append(f"Criterion2 @Test count: {count} (20/20)")
        elif count >= 10:
            score += 14
            feedback.append(f"Criterion2 @Test count: {count} (14/20)")
        elif count >= 5:
            score += 8
            feedback.append(f"Criterion2 @Test count: {count} (8/20)")
        elif count >= 1:
            score += 4
            feedback.append(f"Criterion2 @Test count: {count} (4/20)")
        else:
            feedback.append("Criterion2 @Test count: 0 (0/20)")
    except Exception as e:
        feedback.append(f"Criterion2: error ({e}) (0/20)")

    # ================================================================
    # Criterion 3: At least 2 of 3 classes covered (15 pts)
    # ================================================================
    try:
        covers_loan = bool(re.search(r'LoanCalculator', test_contents, re.IGNORECASE))
        covers_invest = bool(re.search(r'InvestmentAnalyzer', test_contents, re.IGNORECASE))
        covers_budget = bool(re.search(r'BudgetPlanner', test_contents, re.IGNORECASE))
        classes_covered = sum([covers_loan, covers_invest, covers_budget])

        if classes_covered == 3:
            score += 15
            feedback.append("Criterion3 Coverage: all 3 classes (15/15)")
        elif classes_covered == 2:
            score += 10
            feedback.append(f"Criterion3 Coverage: 2 classes (10/15)")
        elif classes_covered == 1:
            score += 5
            feedback.append(f"Criterion3 Coverage: 1 class (5/15)")
        else:
            feedback.append("Criterion3 Coverage: no target classes referenced (0/15)")
    except Exception as e:
        feedback.append(f"Criterion3: error ({e}) (0/15)")

    # ================================================================
    # Criterion 4: Edge case / exception tests (20 pts)
    # ================================================================
    try:
        # Look for patterns that indicate edge case / exception testing
        has_assert_throws = bool(re.search(
            r'assertThrows|Assert\.assertThrows|shouldThrow|assertFailsWith',
            test_contents
        ))
        has_zero_test = bool(re.search(
            r'0\.0|0,\s*0|principal\s*=\s*0|rate\s*=\s*0|zero|Zero',
            test_contents
        ))
        has_negative_test = bool(re.search(
            r'-\d+\.?\d*|-\d+|negative|Negative',
            test_contents
        ))
        has_boundary = bool(re.search(
            r'min|max|MAX|MIN|boundary|Boundary|edge|Edge',
            test_contents, re.IGNORECASE
        ))
        has_assertions = bool(re.search(
            r'assertEquals|assertThat|assertTrue|assertFalse|assertNotNull',
            test_contents
        ))

        ec_score = 0
        if has_assert_throws:
            ec_score += 8
        if has_zero_test or has_negative_test:
            ec_score += 6
        if has_boundary:
            ec_score += 3
        if has_assertions:
            ec_score += 3

        score += min(ec_score, 20)
        feedback.append(f"Criterion4 Edge cases: ({min(ec_score, 20)}/20) "
                        f"[throws={has_assert_throws}, zero={has_zero_test}, "
                        f"negative={has_negative_test}, assertions={has_assertions}]")
    except Exception as e:
        feedback.append(f"Criterion4: error ({e}) (0/20)")

    # ================================================================
    # Criterion 5: All tests pass (30 pts)
    # ================================================================
    try:
        # Re-check from gradle log
        if not test_success:
            gradle_log = _read_text(copy_from_env, "/tmp/test_output.log")
            if gradle_log and "BUILD SUCCESSFUL" in gradle_log:
                test_success = True
            elif gradle_log and "tests were successful" in gradle_log.lower():
                test_success = True

        if test_success and test_failed == 0:
            score += 30
            feedback.append(f"Criterion5 Tests pass: all passed ({test_passed} tests) (30/30)")
        elif test_success:
            score += 20
            feedback.append(f"Criterion5 Tests pass: build ok but {test_failed} failures (20/30)")
        elif test_passed > 0 and test_failed == 0:
            score += 25
            feedback.append(f"Criterion5 Tests pass: {test_passed} passed, build log unclear (25/30)")
        elif test_passed > 0:
            # Some tests ran and passed
            ratio = test_passed / max(test_passed + test_failed, 1)
            partial = int(30 * ratio * 0.7)
            score += partial
            feedback.append(f"Criterion5 Tests pass: {test_passed}/{test_passed+test_failed} passed ({partial}/30)")
        else:
            feedback.append("Criterion5 Tests pass: tests failed or didn't run (0/30)")
    except Exception as e:
        feedback.append(f"Criterion5: error ({e}) (0/30)")

    passed = score >= 70

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback)
    }
