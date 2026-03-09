"""
Verifier for qa_test_suite_coverage task.

Scoring (100 points):
  - Test file meaningfully modified (not placeholder only):    10 pts
  - Covers LoanCalculator (3+ test methods implied):           15 pts
  - Covers CompoundInterestEngine (3+ test methods implied):   15 pts
  - Covers CurrencyConverter (3+ test methods implied):        15 pts
  - Exception/error cases tested:                              10 pts
  - Edge cases tested (zero/boundary values):                   5 pts
  - Total test method count >= 9:                              10 pts
  - All tests pass (0 failures):                               10 pts
  - Build: 0 errors:                                           10 pts

Pass threshold: 60 points
"""

import json
import os
import re
import shutil
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\qa_test_suite_coverage_result.json"
TEST_PATH   = "C:\\Users\\Docker\\source\\repos\\FinancialCalc\\src\\FinancialCalc.Tests\\FinancialCalcTests.cs"


def _has(pattern, text, flags=re.IGNORECASE | re.DOTALL):
    return bool(re.search(pattern, text, flags))


def _count_pattern(pattern, text, flags=re.IGNORECASE):
    return len(re.findall(pattern, text, flags))


def verify_qa_test_suite_coverage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.mkdtemp(prefix="verify_qatests_")
    try:
        # --- Step 1: Read export result JSON ---
        result = {}
        json_local = os.path.join(tmp, "result.json")
        try:
            copy_from_env(RESULT_PATH, json_local)
            with open(json_local, encoding="utf-8-sig") as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0,
                    "feedback": "Result JSON not found — export script may not have run"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Cannot read result JSON: {e}"}

        # --- Anti-gaming gate ---
        if not result.get("test_file_modified", False):
            return {"passed": False, "score": 0,
                    "feedback": "Test file was not modified — no work detected"}

        # --- Step 2: Independently read test file ---
        test_src = ""
        test_local = os.path.join(tmp, "FinancialCalcTests.cs")
        try:
            copy_from_env(TEST_PATH, test_local)
            with open(test_local, encoding="utf-8-sig") as f:
                test_src = f.read()
        except Exception:
            test_src = ""

        score = 0
        fb    = []

        # ── Placeholder check ─────────────────────────────────────────────────
        has_placeholder = _has(r"Placeholder_AlwaysPasses|Replace this placeholder", test_src) \
            if test_src else result.get("placeholder_present", True)

        # ── Count test methods ────────────────────────────────────────────────
        fact_count   = _count_pattern(r"\[Fact\]", test_src) if test_src else result.get("fact_count", 0)
        theory_count = _count_pattern(r"\[Theory\]", test_src) if test_src else result.get("theory_count", 0)
        total_tests  = fact_count + theory_count if test_src else result.get("total_test_methods", 0)

        # ── Class coverage ────────────────────────────────────────────────────
        covers_loan     = _has(r"LoanCalculator", test_src) if test_src else result.get("covers_loan", False)
        covers_compound = _has(r"CompoundInterestEngine", test_src) if test_src else result.get("covers_compound", False)
        covers_currency = _has(r"CurrencyConverter", test_src) if test_src else result.get("covers_currency", False)

        # ── Exception testing ─────────────────────────────────────────────────
        tests_exceptions = _has(r"Assert\.Throws|ThrowsException|ArgumentException|InvalidOperationException", test_src) \
            if test_src else result.get("tests_exceptions", False)

        # ── Edge case testing ─────────────────────────────────────────────────
        tests_edge = _has(r"0\.0|annualRate.*0|rate.*0|zero|edge|boundary|termMonths.*1\b|years.*0", test_src) \
            if test_src else result.get("tests_edge_cases", False)

        # ── Criterion 1: File meaningfully modified (10 pts) ─────────────────
        if not has_placeholder and (covers_loan or covers_compound or covers_currency):
            score += 10
            fb.append("Test file contains real tests (not placeholder) (+10)")
        elif has_placeholder and total_tests > 1:
            score += 5
            fb.append("Test file has some tests but placeholder still present (+5)")
        else:
            fb.append("Test file appears unchanged or only has placeholder (0/10)")

        # ── Criterion 2: LoanCalculator coverage (15 pts) ────────────────────
        if covers_loan:
            score += 15
            fb.append("LoanCalculator tests present (+15)")
        else:
            fb.append("No LoanCalculator tests found (0/15)")

        # ── Criterion 3: CompoundInterestEngine coverage (15 pts) ─────────────
        if covers_compound:
            score += 15
            fb.append("CompoundInterestEngine tests present (+15)")
        else:
            fb.append("No CompoundInterestEngine tests found (0/15)")

        # ── Criterion 4: CurrencyConverter coverage (15 pts) ──────────────────
        if covers_currency:
            score += 15
            fb.append("CurrencyConverter tests present (+15)")
        else:
            fb.append("No CurrencyConverter tests found (0/15)")

        # ── Criterion 5: Exception testing (10 pts) ───────────────────────────
        if tests_exceptions:
            score += 10
            fb.append("Exception/error scenarios tested (+10)")
        else:
            fb.append("No exception testing found — Assert.Throws<> missing (0/10)")

        # ── Criterion 6: Edge cases (5 pts) ───────────────────────────────────
        if tests_edge:
            score += 5
            fb.append("Edge cases tested (zero rate, single period, etc.) (+5)")
        else:
            fb.append("No edge case tests detected (0/5)")

        # ── Criterion 7: Minimum test count >= 9 (10 pts) ────────────────────
        if total_tests >= 9:
            score += 10
            fb.append(f"Test count: {total_tests} >= 9 minimum (+10)")
        elif total_tests >= 5:
            score += 5
            fb.append(f"Test count: {total_tests} — below 9 minimum (+5)")
        else:
            fb.append(f"Test count: {total_tests} — far below 9 minimum (0/10)")

        # ── Criterion 8: All tests pass (10 pts) ──────────────────────────────
        all_pass = result.get("all_tests_passed", False)
        t_pass   = result.get("tests_passed", 0)
        t_fail   = result.get("tests_failed", 0)

        if all_pass and t_pass >= 1:
            score += 10
            fb.append(f"All {t_pass} tests pass (+10)")
        elif t_fail > 0:
            fb.append(f"{t_fail} test(s) failing — fix assertions (0/10)")
        else:
            fb.append("Tests did not run or no passing tests (0/10)")

        # ── Build gate (10 pts) ───────────────────────────────────────────────
        build_success = result.get("build_success", False)
        build_errors  = result.get("build_errors", 999)

        if build_success and build_errors == 0:
            score += 10
            fb.append("Build: OK — 0 errors (+10)")
        else:
            if score > 40:
                score = 40
                fb.append(f"BUILD FAILED ({build_errors} errors) — score capped at 40")
            else:
                fb.append(f"BUILD FAILED ({build_errors} errors)")

        passed = score >= 60
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(fb)
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
