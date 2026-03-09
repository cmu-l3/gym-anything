#!/usr/bin/env python3
"""
Verifier for Fix Regional Sites task.

Occupation: Online Merchant
Task: Correct currency, timezone, and ecommerce on three misconfigured regional sites.

Scoring (100 points):
  UK Fashion Store:
    - currency = GBP:             10 pts
    - timezone = Europe/London:   10 pts
    - ecommerce enabled:           5 pts
  German Auto Parts:
    - currency = EUR:             10 pts
    - timezone = Europe/Berlin:   10 pts
    - ecommerce enabled:           5 pts
  Tokyo Electronics:
    - currency = JPY:             10 pts
    - timezone = Asia/Tokyo:      10 pts
    - ecommerce enabled:           5 pts
  All three fully correct (bonus): 25 pts

Wrong-target GATE: If Initial Site was modified → score = 0 immediately.
Pass threshold: >= 70 points AND Initial Site unmodified.
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED = {
    "uk_fashion_store": {
        "currency": "GBP",
        "timezone": "Europe/London",
        "ecommerce": 1,
    },
    "german_auto_parts": {
        "currency": "EUR",
        # Accept either Berlin spelling
        "timezone": "Europe/Berlin",
        "ecommerce": 1,
    },
    "tokyo_electronics": {
        "currency": "JPY",
        "timezone": "Asia/Tokyo",
        "ecommerce": 1,
    },
}


def _ecommerce_on(val: Any) -> bool:
    try:
        return int(val) == 1
    except (TypeError, ValueError):
        return str(val).strip() == "1"


def _timezone_match(actual: str, expected: str) -> bool:
    """Case-insensitive, strip comparison."""
    return actual.strip().lower() == expected.strip().lower()


def _currency_match(actual: str, expected: str) -> bool:
    return actual.strip().upper() == expected.strip().upper()


def verify_fix_regional_sites(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the three regional sites were correctly reconfigured."""

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/fix_regional_sites_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run",
        }
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving result: {e}"}

    # ── WRONG-TARGET GATE ─────────────────────────────────────────────────
    initial_site_modified = (
        str(result.get("initial_site_modified", "false")).lower() == "true"
    )
    if initial_site_modified:
        logger.warning("Initial Site was modified — wrong-target gate triggered")
        return {
            "passed": False, "score": 0,
            "feedback": (
                "WRONG-TARGET: The 'Initial Site' was modified. "
                "Only the three regional sites should be changed. Score=0."
            ),
            "subscores": {},
        }

    score = 0
    feedback = []
    subscores: Dict[str, bool] = {}

    site_map = {
        "uk_fashion_store": "UK Fashion Store",
        "german_auto_parts": "German Auto Parts",
        "tokyo_electronics": "Tokyo Electronics",
    }
    result_keys = {
        "uk_fashion_store": result.get("uk_fashion_store", {}),
        "german_auto_parts": result.get("german_auto_parts", {}),
        "tokyo_electronics": result.get("tokyo_electronics", {}),
    }

    all_correct = True

    for key, display_name in site_map.items():
        exp = EXPECTED[key]
        data = result_keys[key]
        site_all_ok = True

        logger.info("Checking %s: %s", display_name, data)

        # Currency
        actual_currency = str(data.get("currency", "")).strip()
        if _currency_match(actual_currency, exp["currency"]):
            score += 10
            subscores[f"{key}_currency"] = True
            feedback.append(f"{display_name}: currency={actual_currency} ✓ [+10]")
        else:
            subscores[f"{key}_currency"] = False
            site_all_ok = False
            feedback.append(
                f"{display_name}: currency expected {exp['currency']}, "
                f"got '{actual_currency}' [-10]"
            )

        # Timezone
        actual_tz = str(data.get("timezone", "")).strip()
        if _timezone_match(actual_tz, exp["timezone"]):
            score += 10
            subscores[f"{key}_timezone"] = True
            feedback.append(f"{display_name}: timezone={actual_tz} ✓ [+10]")
        else:
            subscores[f"{key}_timezone"] = False
            site_all_ok = False
            feedback.append(
                f"{display_name}: timezone expected {exp['timezone']}, "
                f"got '{actual_tz}' [-10]"
            )

        # Ecommerce
        actual_ecom = data.get("ecommerce", 0)
        if _ecommerce_on(actual_ecom):
            score += 5
            subscores[f"{key}_ecommerce"] = True
            feedback.append(f"{display_name}: ecommerce=1 ✓ [+5]")
        else:
            subscores[f"{key}_ecommerce"] = False
            site_all_ok = False
            feedback.append(f"{display_name}: ecommerce NOT enabled [-5]")

        if not site_all_ok:
            all_correct = False

    # Bonus: all three fully correct
    if all_correct:
        score += 25
        subscores["all_three_complete"] = True
        feedback.append("All three regional sites fully correct [+25 bonus]")
    else:
        subscores["all_three_complete"] = False

    passed = score >= 70 and not initial_site_modified

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "expected": EXPECTED,
            "actual": {k: result_keys[k] for k in result_keys},
            "initial_site_modified": initial_site_modified,
        },
    }
