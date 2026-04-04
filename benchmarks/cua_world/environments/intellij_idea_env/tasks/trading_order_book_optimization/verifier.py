#!/usr/bin/env python3
"""Verifier for trading_order_book_optimization task."""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _strip_java_comments(src):
    """Strip // and /* */ comments so Javadoc fix-hints do not trigger verifier patterns."""
    src = re.sub(r'/\*.*?\*/', ' ', src, flags=re.DOTALL)  # block / Javadoc comments
    src = re.sub(r'//[^\n]*', '', src)                      # single-line comments
    return src


def verify_trading_order_book_optimization(traj, env_info, task_info):
    """
    Verify that all three bugs in the trading order book were fixed.

    Scoring (100 points total):
    - Bug 1 fixed: OrderBook maintains sorted bid/ask order (30 pts)
    - Bug 2 fixed: MatchingEngine uses >= for price comparison (25 pts)
    - Bug 3 fixed: Order.fillQuantity() does not mutate orderedQuantity (25 pts)
    - All tests pass (10 pts)
    - Test file unmodified (5 pts / -10 pts penalty)
    - VLM bonus: up to 5 pts

    Pass threshold: score >= 70 AND all tests pass
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/trading-orderbook')
    expected_tests = metadata.get('expected_test_count', 6)

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

    order_src  = result.get('order_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/trading/Order.java") or ''
    book_src   = result.get('orderbook_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/trading/OrderBook.java") or ''
    engine_src = result.get('engine_source', '') or \
                 copy_and_read(f"{project_dir}/src/main/java/com/trading/MatchingEngine.java") or ''

    # Strip comments so Javadoc fix-hints (e.g. "Use a {@link TreeMap}") don't trigger patterns
    book_src_clean   = _strip_java_comments(book_src)
    order_src_clean  = _strip_java_comments(order_src)
    engine_src_clean = _strip_java_comments(engine_src)

    # -----------------------------------------------------------------------
    # Criterion 1: OrderBook maintains sorted bid/ask order (30 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix: use a sorted data structure (TreeMap, PriorityQueue, sorted insertion)
        # Use comment-stripped source to avoid matching Javadoc hints like "{@link TreeMap}"
        has_tree_map      = 'TreeMap' in book_src_clean or 'NavigableMap' in book_src_clean
        has_priority_q    = 'PriorityQueue' in book_src_clean
        has_sorted_insert = bool(re.search(r'Comparator|\.sort\(|Collections\.sort', book_src_clean))
        # Bug pattern: plain ArrayList add() without sorting
        still_plain_add   = bool(re.search(r'bids\.add\(|asks\.add\(', book_src_clean)) and \
                            not (has_tree_map or has_priority_q or has_sorted_insert)

        if has_tree_map or has_priority_q or (has_sorted_insert and not still_plain_add):
            score += 30
            method = 'TreeMap' if has_tree_map else ('PriorityQueue' if has_priority_q else 'sorted insertion')
            feedback_parts.append(f"OrderBook: sorted structure used ({method}) (Bug 1 fixed)")
        elif has_sorted_insert:
            score += 20
            feedback_parts.append("OrderBook: sort/comparator present but plain add() also found — verify sorting is applied on add")
        else:
            feedback_parts.append("OrderBook: still uses unsorted ArrayList — getBestBid()/getBestAsk() return wrong orders (Bug 1 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 1 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 2: MatchingEngine uses >= for price comparison (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Fix: bid.getLimitPrice() >= ask.getLimitPrice()
        has_gte = bool(re.search(r'getLimitPrice\(\)\s*>=\s*\w+\.getLimitPrice\(\)', engine_src_clean))
        has_gt  = bool(re.search(r'getLimitPrice\(\)\s*>\s*\w+\.getLimitPrice\(\)', engine_src_clean))

        if has_gte and not has_gt:
            score += 25
            feedback_parts.append("MatchingEngine: uses >= for price comparison — at-par matches enabled (Bug 2 fixed)")
        elif has_gte:
            score += 12
            feedback_parts.append("MatchingEngine: >= present but strict > also found — check logic")
        else:
            feedback_parts.append("MatchingEngine: still uses strict > — at-par orders never match (Bug 2 not fixed)")
    except Exception as e:
        logger.debug(f"Criterion 2 check failed: {e}")

    # -----------------------------------------------------------------------
    # Criterion 3: Order.fillQuantity() does not mutate orderedQuantity (25 pts)
    # -----------------------------------------------------------------------
    try:
        # Bug pattern: orderedQuantity -= qty in fillQuantity body
        has_ordered_qty_mutated = bool(re.search(
            r'orderedQuantity\s*-=\s*qty',
            order_src_clean
        ))
        # fillQuantity body should only modify filledQuantity
        has_filled_qty_updated = bool(re.search(r'filledQuantity\s*\+=', order_src_clean))

        if has_filled_qty_updated and not has_ordered_qty_mutated:
            score += 25
            feedback_parts.append("Order.fillQuantity(): orderedQuantity mutation removed, filledQuantity updated correctly (Bug 3 fixed)")
        elif not has_ordered_qty_mutated:
            score += 15
            feedback_parts.append("Order.fillQuantity(): orderedQuantity mutation gone but filledQuantity update unclear")
        else:
            feedback_parts.append("Order.fillQuantity(): still modifies orderedQuantity — remaining quantity tracks at 2× the error (Bug 3 not fixed)")
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
                feedback_parts.append("WARNING: OrderBookTest.java was modified — penalty applied")
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
                "Fix three bugs in trading-orderbook: "
                "(1) OrderBook must maintain sorted bid (high→low) and ask (low→high) order, "
                "(2) MatchingEngine must use >= (not >) for price comparison, "
                "(3) Order.fillQuantity() must not modify orderedQuantity. "
                "All 6 tests in OrderBookTest must pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the trading-orderbook project",
                "Implementation files were edited",
                "Tests were run and all pass",
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
        feedback_parts.append("NOTE: Task incomplete — all 6 tests must pass with 0 failures")

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
