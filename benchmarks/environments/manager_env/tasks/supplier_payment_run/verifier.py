#!/usr/bin/env python3
"""
Verifier for supplier_payment_run task.

Reads the JSON exported by export_result.sh via copy_from_env.

Scoring (100 points, pass >= 65):
  20 pts  Debit note for Pavlova ~$200 (must be new)
  20 pts  Payment to Pavlova ~$1,320 (after debit note applied)
  20 pts  Payment to Specialty Biscuits ~$2,430
  20 pts  Payment to Grandma Kelly's ~$1,890
  20 pts  Non-overdue invoices NOT paid ($875 Pavlova, $1,080 Exotic Liquids)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_supplier_payment_run(traj, env_info, task_info):
    """Verify supplier payment run task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/supplier_payment_run_result.json", tmp.name)
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
    new_payments = result.get("new_payment_count", 0)
    new_debit_notes = result.get("new_debit_note_count", 0)

    # Criterion 1: Debit note for Pavlova ~$200 (20 pts)
    c1 = result.get("has_pavlova_debit_note_200", False) and new_debit_notes > 0
    if c1:
        score += 20
    criteria["debit_note_pavlova_200"] = {"passed": c1, "points": 20 if c1 else 0, "max_points": 20}

    # Criterion 2: Payment to Pavlova ~$1,320 (20 pts)
    c2 = result.get("has_pavlova_payment_1320", False) and new_payments > 0
    if c2:
        score += 20
    criteria["payment_pavlova_1320"] = {"passed": c2, "points": 20 if c2 else 0, "max_points": 20}

    # Criterion 3: Payment to Specialty Biscuits ~$2,430 (20 pts)
    c3 = result.get("has_specialty_biscuits_payment_2430", False) and new_payments > 0
    if c3:
        score += 20
    criteria["payment_specialty_biscuits_2430"] = {"passed": c3, "points": 20 if c3 else 0, "max_points": 20}

    # Criterion 4: Payment to Grandma Kelly's ~$1,890 (20 pts)
    c4 = result.get("has_grandma_kellys_payment_1890", False) and new_payments > 0
    if c4:
        score += 20
    criteria["payment_grandma_kellys_1890"] = {"passed": c4, "points": 20 if c4 else 0, "max_points": 20}

    # Criterion 5: Non-overdue invoices NOT paid (20 pts)
    # Requires at least 1 payment made (agent did work) but correctly excluded non-overdue
    c5 = (new_payments > 0
          and result.get("no_pavlova_875_payment", True)
          and result.get("no_exotic_1080_payment", True))
    if c5:
        score += 20
    criteria["non_overdue_not_paid"] = {
        "passed": c5, "points": 20 if c5 else 0, "max_points": 20,
        "details": {"no_pavlova_875": result.get("no_pavlova_875_payment"),
                    "no_exotic_1080": result.get("no_exotic_1080_payment")}
    }

    passed = score >= 65
    feedback_parts = [f"Score: {score}/100"]
    for name, c in criteria.items():
        feedback_parts.append(f"  [{'PASS' if c['passed'] else 'FAIL'}] {name}: {c['points']}/{c['max_points']} pts")
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback_parts), "criteria": criteria}
