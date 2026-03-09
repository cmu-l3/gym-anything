#!/usr/bin/env python3
"""
Verifier for bank_account_reconciliation task.

Reads the JSON exported by export_result.sh via copy_from_env.

Scoring (100 points, pass >= 65):
  20 pts  Business Checking Account created
  25 pts  Bank charges JE $35 balanced
  25 pts  Transfer JE $5,000 balanced
  15 pts  Both JEs present and balanced
  15 pts  Bank accounts list shows 2+ accounts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_bank_account_reconciliation(traj, env_info, task_info):
    """Verify bank account reconciliation task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/bank_account_reconciliation_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    criteria = {}
    new_ba = result.get("new_ba_count", 0)

    c1 = result.get("business_checking_exists", False) and new_ba > 0
    if c1:
        score += 20
    criteria["business_checking_created"] = {"passed": c1, "points": 20 if c1 else 0, "max_points": 20}

    c2 = result.get("je_bank_charges_ok", False)
    if c2:
        score += 25
    criteria["je_bank_charges_35"] = {
        "passed": c2, "points": 25 if c2 else 0, "max_points": 25,
        "details": {"in_list": result.get("je_35_in_list"), "balanced": result.get("je_35_balanced")}
    }

    c3 = result.get("je_transfer_ok", False)
    if c3:
        score += 25
    criteria["je_transfer_5000"] = {
        "passed": c3, "points": 25 if c3 else 0, "max_points": 25,
        "details": {"in_list": result.get("je_5000_in_list"), "balanced": result.get("je_5000_balanced")}
    }

    c4 = result.get("both_jes_ok", False)
    if c4:
        score += 15
    criteria["both_jes_balanced"] = {"passed": c4, "points": 15 if c4 else 0, "max_points": 15}

    c5 = result.get("bank_accounts_2_plus", False)
    if c5:
        score += 15
    criteria["bank_accounts_2_plus"] = {
        "passed": c5, "points": 15 if c5 else 0, "max_points": 15,
        "details": {"current_count": result.get("current_bank_account_count")}
    }

    passed = score >= 65
    feedback_parts = [f"Score: {score}/100"]
    for name, c in criteria.items():
        feedback_parts.append(f"  [{'PASS' if c['passed'] else 'FAIL'}] {name}: {c['points']}/{c['max_points']} pts")
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback_parts), "criteria": criteria}
