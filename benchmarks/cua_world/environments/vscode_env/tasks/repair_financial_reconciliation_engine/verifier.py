#!/usr/bin/env python3
"""
Verifier for the repair_financial_reconciliation_engine task.

Checks whether the agent identified and fixed 5 critical bugs in
the bank reconciliation engine.

Each fix is worth 20 points (total 100).  Pass threshold: 60.
"""

import sys
import os
import json
import re
import hashlib
import logging
import tempfile
import shutil

sys.path.insert(
    0,
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../", "utils"),
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ──────────────────────────────────────────────────────────
# Helper utilities
# ──────────────────────────────────────────────────────────

def _safe_get(data, key):
    """Return file content from the result dict, or empty string."""
    val = data.get(key)
    return val if isinstance(val, str) else ""


def _md5(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


# ──────────────────────────────────────────────────────────
# Individual bug checks
# ──────────────────────────────────────────────────────────

def check_decimal_tolerance_matching(matcher_src):
    """
    Bug 1 -- Float equality for amounts (engine/matcher.py)
    The original code uses `if bank_amount == ledger_amount` with floats.
    Fix: use Decimal comparison, tolerance-based matching, or call
    within_tolerance().
    """
    if not matcher_src:
        return False, "engine/matcher.py is missing or empty"

    # The buggy pattern: direct float equality on amounts
    # Look for the exact bug pattern: comparing bank_amount == ledger_amount
    # where both are float()
    has_float_equality = bool(
        re.search(r'bank_amount\s*==\s*ledger_amount', matcher_src)
    )

    # Check for correct patterns
    has_decimal = bool(re.search(r'Decimal', matcher_src))
    has_tolerance = bool(
        re.search(r'within_tolerance', matcher_src)
        or re.search(r'abs\s*\(\s*(?:bank|ledger|a|b|amount)', matcher_src)
    )
    has_isclose = bool(re.search(r'isclose|math\.isclose', matcher_src))

    if has_float_equality:
        return False, "matcher.py still uses direct float == comparison for amounts"

    if has_decimal or has_tolerance or has_isclose:
        return True, "matcher.py correctly avoids float equality (uses Decimal/tolerance)"

    # If the == is gone but no clear replacement, check that float() is also gone
    # or that some comparison logic exists
    if not re.search(r'==\s*ledger_amount', matcher_src):
        return True, "matcher.py no longer uses direct float equality comparison"

    return False, "matcher.py may still use problematic float comparison"


def check_fx_spread_applied(fx_handler_src):
    """
    Bug 2 -- Missing bid/ask spread (engine/fx_handler.py)
    The original code sets `effective_rate = mid_rate` without applying
    the spread. Fix: apply spread based on direction (buy/sell).
    """
    if not fx_handler_src:
        return False, "engine/fx_handler.py is missing or empty"

    # The buggy pattern: effective_rate = mid_rate (without spread)
    still_buggy = bool(
        re.search(r'effective_rate\s*=\s*mid_rate\s*$', fx_handler_src, re.MULTILINE)
    )

    # Check for spread application in the convert_to_base method
    has_spread_applied = bool(
        re.search(r'spread', fx_handler_src)
        and (
            re.search(r'\*\s*\(\s*1\s*[\+\-]', fx_handler_src)
            or re.search(r'mid_rate\s*\*', fx_handler_src)
            and re.search(r'spread', fx_handler_src)
        )
    )

    # Check if effective_rate is now computed with spread
    has_effective_with_spread = bool(
        re.search(r'effective_rate\s*=\s*mid_rate\s*\*', fx_handler_src)
        or re.search(r'effective_rate\s*=.*spread', fx_handler_src)
        or re.search(r'effective_rate\s*=.*\(\s*1\s*[\+\-]', fx_handler_src)
    )

    if still_buggy and not has_effective_with_spread:
        return False, "fx_handler.py still uses mid-rate without spread"

    if has_effective_with_spread or has_spread_applied:
        return True, "fx_handler.py correctly applies bid/ask spread to FX conversion"

    # If effective_rate = mid_rate is gone, check for alternative spread logic
    if not still_buggy:
        # Check that spread is used somewhere in the conversion logic
        if re.search(r'self\.spread|FX_SPREAD', fx_handler_src):
            return True, "fx_handler.py appears to apply FX spread"

    return False, "fx_handler.py does not appear to apply bid/ask spread"


def check_timezone_aware_dates(date_handler_src):
    """
    Bug 3 -- Timezone-naive comparison (engine/date_handler.py)
    The original code parses dates without timezone info.
    Fix: parse with timezone and normalize to same timezone.
    """
    if not date_handler_src:
        return False, "engine/date_handler.py is missing or empty"

    # Check for timezone-aware handling
    tz_patterns = [
        r'pytz',
        r'zoneinfo',
        r'timezone',
        r'tzinfo',
        r'astimezone',
        r'replace\s*\(\s*tzinfo\s*=',
        r'localize',
        r'ZoneInfo',
    ]

    has_tz_handling = any(
        re.search(pat, date_handler_src) for pat in tz_patterns
    )

    # Check that the normalize_dates function no longer just uses bare strptime
    normalize_func = ""
    match = re.search(
        r'def normalize_dates\s*\(.*?\):\s*\n(.*?)(?=\ndef |\Z)',
        date_handler_src,
        re.DOTALL,
    )
    if match:
        normalize_func = match.group(1)

    # Bug pattern: bare strptime without any timezone handling in normalize_dates
    bare_strptime_only = bool(
        re.search(r'strptime', normalize_func)
        and not any(re.search(pat, normalize_func) for pat in tz_patterns)
    )

    if bare_strptime_only and not has_tz_handling:
        return False, "date_handler.py still uses timezone-naive date parsing"

    if has_tz_handling:
        return True, "date_handler.py includes timezone-aware date handling"

    return False, "date_handler.py does not appear to handle timezones"


def check_tolerance_base(tolerance_src):
    """
    Bug 4 -- Wrong tolerance base (engine/tolerance_checker.py)
    The original code calculates tolerance as `abs(bank_dec) * tolerance_pct`.
    Fix: use `max(abs(bank_dec), abs(ledger_dec)) * tolerance_pct`.
    """
    if not tolerance_src:
        return False, "engine/tolerance_checker.py is missing or empty"

    # The buggy pattern: only uses bank_dec as the base
    still_buggy = bool(
        re.search(
            r'tolerance_amount\s*=\s*abs\s*\(\s*bank_dec\s*\)\s*\*\s*tolerance',
            tolerance_src,
        )
    )

    # Correct pattern: max(abs(...), abs(...))
    has_max_abs = bool(
        re.search(r'max\s*\(\s*abs\s*\(', tolerance_src)
    )

    if still_buggy and not has_max_abs:
        return False, "tolerance_checker.py still uses only bank_amount as tolerance base"

    if has_max_abs:
        return True, "tolerance_checker.py correctly uses max(abs()) for tolerance base"

    # Alternative correct patterns
    if not still_buggy:
        # Check for other valid approaches (e.g., using both amounts)
        uses_both = bool(
            re.search(r'bank_dec.*ledger_dec|ledger_dec.*bank_dec', tolerance_src)
            and re.search(r'max|larger|greater', tolerance_src, re.IGNORECASE)
        )
        if uses_both:
            return True, "tolerance_checker.py uses both amounts for tolerance calculation"

    return False, "tolerance_checker.py does not use correct tolerance base"


def check_signed_grouping(reporter_src):
    """
    Bug 5 -- Sign-blind grouping (engine/exception_reporter.py)
    The original code groups by `abs(exc['amount'])`, merging debits
    and credits with the same absolute value.
    Fix: use signed amount or include sign in the grouping key.
    """
    if not reporter_src:
        return False, "engine/exception_reporter.py is missing or empty"

    # The buggy pattern: abs(exc['amount']) as key
    has_abs_key = bool(
        re.search(r"key\s*=\s*abs\s*\(\s*exc\s*\[\s*['\"]amount['\"]\s*\]", reporter_src)
    )

    if has_abs_key:
        return False, "exception_reporter.py still groups by abs(amount), losing sign info"

    # Check for correct patterns: signed amount as key
    correct_patterns = [
        r"key\s*=\s*exc\s*\[\s*['\"]amount['\"]\s*\]",  # signed amount
        r"key\s*=\s*\(\s*exc\s*\[\s*['\"]amount['\"]\s*\]",  # tuple with sign
        r"key\s*=.*sign",  # includes sign
        r"key\s*=\s*float\s*\(\s*exc",  # float(exc['amount'])
        r"key\s*=\s*exc\s*\[\s*['\"]amount",  # direct amount access
    ]

    has_correct = any(
        re.search(pat, reporter_src) for pat in correct_patterns
    )

    if has_correct:
        return True, "exception_reporter.py correctly uses signed amount for grouping"

    # If abs() is gone from the key assignment, that's also a fix
    if not has_abs_key:
        return True, "exception_reporter.py no longer uses abs() for grouping key"

    return False, "exception_reporter.py grouping logic unclear"


# ──────────────────────────────────────────────────────────
# Anti-gaming: verify files were actually changed
# ──────────────────────────────────────────────────────────

def _files_were_modified(data, copy_from_env, temp_dir):
    """
    Compare current file contents against baseline hashes recorded
    during setup.  Returns True if at least one file was modified.
    """
    try:
        hashes_local = os.path.join(temp_dir, "initial_hashes.txt")
        copy_from_env("/tmp/reconciliation_initial_hashes.txt", hashes_local)
        if not os.path.exists(hashes_local):
            return True  # can't verify, assume modified

        with open(hashes_local, "r") as fh:
            original_hashes = {}
            for line in fh:
                parts = line.strip().split()
                if len(parts) >= 2:
                    h, path = parts[0], parts[-1]
                    # Extract relative key
                    for key in data:
                        if path.endswith(key) or path.endswith(key.replace("/", os.sep)):
                            original_hashes[key] = h

        # Check if any monitored file has a different hash now
        for key, orig_hash in original_hashes.items():
            content = data.get(key, "")
            if content and _md5(content) != orig_hash:
                return True

        return False
    except Exception as e:
        logger.warning(f"Could not verify file modification: {e}")
        return True  # fail open


# ──────────────────────────────────────────────────────────
# Main verifier entry point
# ──────────────────────────────────────────────────────────

def verify_reconciliation_engine(traj, env_info, task_info):
    """
    Verify that the agent fixed the 5 bugs in the reconciliation engine.

    Returns
    -------
    dict
        {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_dir = tempfile.mkdtemp(prefix="verify_reconciliation_")

    try:
        # ── Retrieve exported result JSON ───────────────
        result_local = os.path.join(temp_dir, "reconciliation_result.json")
        try:
            copy_from_env("/tmp/reconciliation_result.json", result_local)
        except Exception as e:
            logger.error(f"Could not copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}",
            }

        if not os.path.exists(result_local):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found after export",
            }

        with open(result_local, "r", encoding="utf-8") as fh:
            data = json.load(fh)

        # ── Extract file contents ───────────────────────
        matcher_src = _safe_get(data, "engine/matcher.py")
        fx_handler_src = _safe_get(data, "engine/fx_handler.py")
        date_handler_src = _safe_get(data, "engine/date_handler.py")
        tolerance_src = _safe_get(data, "engine/tolerance_checker.py")
        reporter_src = _safe_get(data, "engine/exception_reporter.py")

        # ── Anti-gaming check ───────────────────────────
        if not _files_were_modified(data, copy_from_env, temp_dir):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No files appear to have been modified from the original.",
            }

        # ── Run the five checks ─────────────────────────
        checks = [
            ("Decimal/tolerance matching", 20, check_decimal_tolerance_matching(matcher_src)),
            ("FX bid/ask spread", 20, check_fx_spread_applied(fx_handler_src)),
            ("Timezone-aware dates", 20, check_timezone_aware_dates(date_handler_src)),
            ("Correct tolerance base", 20, check_tolerance_base(tolerance_src)),
            ("Signed exception grouping", 20, check_signed_grouping(reporter_src)),
        ]

        score = 0
        feedback_lines = []

        for label, points, (ok, msg) in checks:
            if ok:
                score += points
                feedback_lines.append(f"PASS [{points}pts] {label}: {msg}")
            else:
                feedback_lines.append(f"FAIL [ 0pts] {label}: {msg}")

        passed = score >= 60
        feedback_lines.insert(
            0,
            f"{'PASSED' if passed else 'FAILED'}: {score}/100 "
            f"(threshold 60, {sum(1 for _, _, (ok, _) in checks if ok)}/5 bugs fixed)",
        )

        logger.info(f"Score: {score}/100, passed={passed}")
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_lines),
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
        }

    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
