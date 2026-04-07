#!/usr/bin/env python3
"""
Verifier for the fix_ecommerce_i18n_implementation task.

Checks whether the agent successfully resolved 5 i18n bugs:
1. Circular fallback chains & returnNull boolean
2. Template interpolation regex
3. Currency fractional digits
4. Locale-aware dates
5. CLDR-valid plural categories in German JSON

Each fix is worth 20 points (total 100). Pass threshold: 60.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_i18n_implementation(traj, env_info, task_info):
    """
    Verify the i18n implementation fixes.
    Returns: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    validation = result.get("validation", {})
    files = result.get("files", {})
    modified = result.get("modified_during_task", False)

    if not modified:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Files were not modified. Agent did not attempt to fix the bugs."
        }

    if "error" in validation:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Runtime error during programmatic validation check. Ensure code contains valid JavaScript."
        }

    score = 0
    feedback_parts = []

    # ── Bug 1: Config (Fallback & returnNull) ──────────
    if validation.get("configFixed"):
        score += 20
        feedback_parts.append("[+] config.js fixed (no circular loop, returnNull is false)")
    else:
        feedback_parts.append("[-] config.js is still broken (circular fallback chain or returnNull is true)")

    # ── Bug 2: Interpolator Regex ──────────
    if validation.get("interpolatorFixed"):
        score += 20
        feedback_parts.append("[+] interpolator.js fixed (matches single braces {var})")
    else:
        feedback_parts.append("[-] interpolator.js is still broken (variables not interpolated)")

    # ── Bug 3: Currency Format ──────────
    if validation.get("currencyFixed"):
        score += 20
        feedback_parts.append("[+] formatter.js currency fixed (handled JPY without decimals)")
    else:
        feedback_parts.append("[-] formatter.js currency is still broken (hardcoded decimal places)")

    # ── Bug 4: Date Format ──────────
    if validation.get("dateFixed"):
        score += 20
        feedback_parts.append("[+] formatter.js dates fixed (locale-aware date ordering)")
    else:
        feedback_parts.append("[-] formatter.js dates is still broken (hardcoded MM/DD/YYYY)")

    # ── Bug 5: German Plurals ──────────
    if validation.get("pluralsFixed"):
        score += 20
        feedback_parts.append("[+] de.json plurals fixed (removed zero/few/many, retained valid CLDR categories)")
    else:
        feedback_parts.append("[-] de.json plurals is still broken (contains invalid Slavic plural categories)")

    # ── Final determination ──────────
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }