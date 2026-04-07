#!/usr/bin/env python3
"""
Verifier for Configure Global Defaults task.

Checks:
1. Default Timezone updated to Europe/Paris
2. Default Currency updated to EUR
3. Default Report Period updated to Week
4. Default Report Date updated to Yesterday
5. Anti-gaming: Values must have changed from the forced baseline.

Scoring:
- 25 pts: Timezone correct
- 25 pts: Currency correct
- 20 pts: Report Period correct
- 20 pts: Report Date correct
- 10 pts: At least one value changed from baseline (Gate)

Pass threshold: 70 points.
"""

import json
import logging
import os
import tempfile
from typing import Any, Dict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_global_defaults(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        try:
            copy_from_env("/tmp/global_defaults_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}

    # Metadata expectations
    meta = task_info.get("metadata", {})
    exp_tz = meta.get("expected_timezone", "Europe/Paris")
    exp_curr = meta.get("expected_currency", "EUR")
    exp_period = meta.get("expected_report_period", "week")
    exp_date = meta.get("expected_report_date", "yesterday")

    current = result.get("current", {})
    initial = result.get("initial", {})
    changed = result.get("values_changed_from_baseline", False)

    score = 0
    feedback = []

    # Helper for case-insensitive comparison
    def match(val, exp):
        return str(val).strip().lower() == str(exp).strip().lower()

    # 1. Check Timezone
    if match(current.get("timezone"), exp_tz):
        score += 25
        feedback.append(f"Timezone correct ({exp_tz})")
    else:
        feedback.append(f"Timezone incorrect: got '{current.get('timezone')}', expected '{exp_tz}'")

    # 2. Check Currency
    # Matomo might store just 'EUR' or 'EUR - Euro...' depending on internal logic, 
    # usually it's the code 'EUR' in the DB option value.
    # We'll check if expected is contained or equal.
    curr_val = str(current.get("currency", "")).upper()
    if curr_val == exp_curr.upper():
        score += 25
        feedback.append(f"Currency correct ({exp_curr})")
    else:
        feedback.append(f"Currency incorrect: got '{curr_val}', expected '{exp_curr}'")

    # 3. Check Report Period
    if match(current.get("report_period"), exp_period):
        score += 20
        feedback.append(f"Report Period correct ({exp_period})")
    else:
        feedback.append(f"Report Period incorrect: got '{current.get('report_period')}', expected '{exp_period}'")

    # 4. Check Report Date
    if match(current.get("report_date"), exp_date):
        score += 20
        feedback.append(f"Report Date correct ({exp_date})")
    else:
        feedback.append(f"Report Date incorrect: got '{current.get('report_date')}', expected '{exp_date}'")

    # 5. Anti-gaming / Change check
    if changed:
        score += 10
        feedback.append("Settings changed from baseline (+10)")
    else:
        feedback.append("No settings changed from baseline (Potential 'do nothing')")
        # If nothing changed, fail the task regardless of other scores (if defaults happened to match target)
        # But in our setup, defaults are explicitly set to WRONG values, so this is robust.
        # If nothing changed, score is capped at 0.
        if score > 0:
            score = 0
            feedback.append("GATE FAILED: No changes detected.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "current": current,
            "expected": {
                "timezone": exp_tz,
                "currency": exp_curr,
                "period": exp_period,
                "date": exp_date
            }
        }
    }