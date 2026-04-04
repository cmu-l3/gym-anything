#!/usr/bin/env python3
"""Verifier for ecommerce_order_refactoring task."""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ecommerce_order_refactoring(traj, env_info, task_info):
    """
    Verify that all three bugs in OrderManager.java were fixed.

    Scoring (100 points total):
    - Bug 1 fixed: discount threshold >= 10 (not > 10) (25 pts)
    - Bug 2 fixed: subtotal accumulator uses long (not int) (30 pts)
    - Bug 3 fixed: validatePaymentCard() performs actual validation (25 pts)
    - All tests pass (zero failures, zero errors): 10 pts
    - Test file unmodified: 5 pts / -10 pts penalty if modified
    - VLM bonus: up to 5 pts

    Pass threshold: score >= 70 AND all tests pass (tests_run >= 5, failures == 0)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/ecommerce-service')
    expected_tests = metadata.get('expected_test_count', 5)

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

    score = 0
    feedback_parts = []

    tests_run    = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)
    tests_error  = result.get('tests_error', 0)

    mgr_src = result.get('order_manager_source', '') or \
              copy_and_read(f"{project_dir}/src/main/java/com/ecommerce/OrderManager.java") or ''

    # -----------------------------------------------------------------------
    # Criterion 1: Discount threshold fixed to >= 10 (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix: >= 10 must appear (not > 10)
        has_correct_threshold = bool(re.search(r'totalItems\s*>=\s*10', mgr_src))
        has_buggy_threshold   = bool(re.search(r'totalItems\s*>\s*10', mgr_src))

        if has_correct_threshold and not has_buggy_threshold:
            score += 25
            feedback_parts.append("calculateDiscountCents(): discount threshold >= 10 (Bug 1 fixed)")
        elif has_correct_threshold:
            score += 12
            feedback_parts.append("calculateDiscountCents(): >= 10 present but > 10 also remains — check logic")
        else:
            feedback_parts.append("calculateDiscountCents(): still uses > 10 — 10-item orders get no discount (Bug 1 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 1 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: Subtotal accumulator is long (30 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix: 'long total' in calculateSubtotalCents
        has_long_total = bool(re.search(r'\blong\s+total\b', mgr_src))
        has_int_total  = bool(re.search(r'\bint\s+total\b',  mgr_src))

        if has_long_total and not has_int_total:
            score += 30
            feedback_parts.append("calculateSubtotalCents(): accumulator is long — overflow fixed (Bug 2 fixed)")
        elif has_long_total:
            score += 15
            feedback_parts.append("calculateSubtotalCents(): long total present but int total also found — check for duplicates")
        else:
            feedback_parts.append("calculateSubtotalCents(): still uses int total — integer overflow for large orders (Bug 2 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 2 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: validatePaymentCard() performs real validation (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix: must no longer be a bare 'return true' without any checks
        bare_return_true = bool(re.search(
            r'validatePaymentCard[^{]*\{[^}]*return\s+true\s*;[^}]*\}',
            mgr_src, re.DOTALL
        ))
        has_length_check = bool(re.search(r'\.length\(\)|length\s*==\s*1[0-9]', mgr_src))
        has_regex_check  = bool(re.search(r'matches\(|Pattern\.compile|\\d\{', mgr_src))
        has_null_check   = 'cardNumber' in mgr_src and bool(re.search(r'null|blank|isEmpty', mgr_src))
        has_expiry_check = bool(re.search(r'expiryYear|Calendar\.getInstance|LocalDate|Year\.now', mgr_src))

        validation_indicators = sum([has_length_check, has_regex_check, has_null_check, has_expiry_check])

        if not bare_return_true and validation_indicators >= 2:
            score += 25
            feedback_parts.append("validatePaymentCard(): actual validation logic implemented (Bug 3 fixed)")
        elif not bare_return_true and validation_indicators >= 1:
            score += 15
            feedback_parts.append("validatePaymentCard(): some validation added but may be incomplete")
        elif bare_return_true:
            feedback_parts.append("validatePaymentCard(): still returns true without validation (Bug 3 not fixed)")
        else:
            score += 10
            feedback_parts.append("validatePaymentCard(): bare return true removed; validation method unclear")
    except Exception as e:
        logger.debug(f"Criterion 3 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 4: All tests pass (10 pts)
    # -----------------------------------------------------------------------
    all_tests_pass = tests_run >= expected_tests and tests_failed == 0 and tests_error == 0
    if all_tests_pass:
        score += 10
        feedback_parts.append(f"All {tests_run} tests pass")
    elif tests_run > 0:
        feedback_parts.append(f"{tests_run} tests run, {tests_failed} failed, {tests_error} errors")
    else:
        feedback_parts.append("No test results found")

    # -----------------------------------------------------------------------
    # Criterion 5: Test file unmodified (5 pts)
    # -----------------------------------------------------------------------
    try:
        initial_cksum = result.get('test_checksum_initial', '')
        current_cksum = result.get('test_checksum_current', '')
        if initial_cksum and current_cksum:
            if initial_cksum == current_cksum:
                score += 5
                feedback_parts.append("Test file unmodified (correct)")
            else:
                score = max(0, score - 10)
                feedback_parts.append("WARNING: OrderManagerTest.java was modified — penalty applied")
    except Exception:
        pass

    # -----------------------------------------------------------------------
    # VLM bonus (5 pts)
    # -----------------------------------------------------------------------
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Fix three bugs in ecommerce-service/OrderManager.java: "
                "(1) discount threshold >= 10 (not > 10), "
                "(2) calculateSubtotalCents() accumulator must be long (not int), "
                "(3) validatePaymentCard() must perform real validation. "
                "All 5 tests in OrderManagerTest must pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the ecommerce-service project",
                "OrderManager.java was edited in IntelliJ",
                "Tests were run and results are visible",
                "All tests are shown as passing",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 5, 100)
        if vlm_result:
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    passed = score >= 70 and all_tests_pass
    if not all_tests_pass and score >= 60:
        feedback_parts.append("NOTE: Task incomplete — all 5 tests must pass with 0 failures")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "tests_run": tests_run,
            "tests_failed": tests_failed,
            "tests_error": tests_error,
        }
    }
